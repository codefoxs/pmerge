import duckdb, re
from collections import Counter
from sfi import Macro


class PmergeError(Exception):
    pass


def q(name):
    """引号包裹标识符，防止列名撞上 SQL 关键字（year/order/case ...）"""
    return '"' + name.replace('"', '""') + '"'


_REF = re.compile(r"\b([ab])\.([A-Za-z_][A-Za-z0-9_]*)")
_STR = re.compile(r"('(?:[^']|'')*')")


def build(con):
    """解析 Stata 传进来的选项，返回 (SQL, 需要在 ado 端改回的列名对)"""
    master_pq = Macro.getLocal("master_pq").replace("\\", "/")
    using_pq = Macro.getLocal("using_pq").replace("\\", "/")
    output_pq = Macro.getLocal("output_pq").replace("\\", "/")
    sql_on = Macro.getLocal("sql_on")
    keepusing_vars = Macro.getLocal("keepusing_vars")
    jointype = Macro.getLocal("jointype")
    keepcase_vars = Macro.getLocal("keepcase_vars")
    where_clause = Macro.getLocal("where_clause")
    merge_var = Macro.getLocal("merge_var")
    nogen = Macro.getLocal("nogen")

    # ── 取 parquet 的真实列名 ────────────────────────────────────────────
    # 不能用 DESCRIBE / read_parquet 拿列名：DuckDB 的标识符大小写不敏感，
    # 会把 lev/LEV 这种「同名不同 case」的列自动改成 lev/LEV_1，
    # 而且 a.LEV（甚至 a."LEV"）会静默解析到 a.lev —— 数据错了还不报错。
    # parquet_schema 读的是文件元数据，返回的才是 Stata 存进去的原始变量名。
    def true_cols(path):
        rows = con.execute(
            "SELECT name FROM parquet_schema(?) WHERE num_children IS NULL", [path]
        ).fetchall()
        return [r[0] for r in rows]

    master_cols = true_cols(master_pq)
    using_cols = true_cols(using_pq)

    # ── 给大小写冲突的列分配无冲突的内部句柄 ─────────────────────────────
    # 只有真正冲突的列才换名，其余列保留原名，
    # 这样用户在 where()/on 里写的不带表前缀的列名仍然照常可用。
    def make_handles(cols, side):
        cnt = Counter(c.lower() for c in cols)
        return [
            "__pm_{}{}".format(side, i) if cnt[c.lower()] > 1 else c
            for i, c in enumerate(cols)
        ]

    sides = {
        "a": (master_cols, make_handles(master_cols, "a"), "master"),
        "b": (using_cols, make_handles(using_cols, "b"), "using"),
    }

    def find_col(side, name):
        """定位列下标：先精确匹配（Stata 语义），再退回唯一的忽略大小写匹配"""
        cols = sides[side][0]
        if name in cols:
            return cols.index(name)
        hits = [i for i, c in enumerate(cols) if c.lower() == name.lower()]
        if len(hits) == 1:
            return hits[0]
        if len(hits) > 1:
            raise PmergeError(
                "{}.{} is ambiguous: {} data has {} -- spell it exactly".format(
                    side, name, sides[side][2],
                    " and ".join(cols[i] for i in hits),
                )
            )
        return None

    def ref(side, name):
        """返回 (SQL 表达式, 该列在 Stata 里的真实变量名)"""
        if side not in sides:
            raise PmergeError("unknown table prefix '{}.' (only a. and b.)".format(side))
        i = find_col(side, name)
        if i is None:
            raise PmergeError(
                "variable {} not found in {} data".format(name, sides[side][2])
            )
        return "{}.{}".format(side, q(sides[side][1][i])), sides[side][0][i]

    def ref_text(token):
        """处理 'a.stkcd' 这种带表前缀的写法"""
        if "." not in token:
            raise PmergeError("'{}' must be written as a.var or b.var".format(token))
        side, name = token.split(".", 1)
        return ref(side, name)

    def rewrite(expr):
        """把 on()/where() 里的 a.xxx / b.xxx 换成内部句柄，字符串字面量原样保留"""
        if not expr:
            return expr
        out = []
        for i, seg in enumerate(_STR.split(expr)):
            if i % 2 == 1:
                out.append(seg)
            else:
                out.append(_REF.sub(lambda m: ref(m.group(1), m.group(2))[0], seg))
        return "".join(out)

    # ── 解析 keepcase ────────────────────────────────────────────────────
    kc_groups = []
    case_aliases = set()
    if keepcase_vars and keepcase_vars.strip():
        for group in keepcase_vars.split("|"):
            parts = group.split()
            if len(parts) not in (2, 3):
                continue
            a_expr, a_name = ref_text(parts[0])
            b_expr, _ = ref_text(parts[1])
            alias = parts[2] if len(parts) == 3 else a_name
            kc_groups.append((a_expr, b_expr, alias))
            case_aliases.add(alias)

    # ── 组装输出列：(SQL 表达式, Stata 变量名) ───────────────────────────
    out_cols = [
        ("CASE WHEN {0} IS NOT NULL THEN {0} ELSE {1} END".format(a_expr, b_expr), alias)
        for a_expr, b_expr, alias in kc_groups
    ]

    def expand(side):
        """展开 a.* / b.*：master 列保持原名，using 端「完全同名」的列加 _1 后缀"""
        if side not in sides:
            raise PmergeError("unknown table prefix '{}.' (only a. and b.)".format(side))
        cols, handles, _ = sides[side]
        for c, h in zip(cols, handles):
            if c in case_aliases:
                continue
            name = c + "_1" if (side == "b" and c in master_cols) else c
            out_cols.append(("{}.{}".format(side, q(h)), name))

    if keepusing_vars and keepusing_vars.strip():
        if keepusing_vars.strip() == "*":
            expand("a")
            expand("b")
        else:
            for v in keepusing_vars.split():
                if "." in v:
                    prefix, col = v.split(".", 1)
                    if col == "*":
                        expand(prefix)
                    else:
                        out_cols.append(ref_text(v))
                elif find_col("b", v) is not None:
                    out_cols.append(ref("b", v))
                else:
                    out_cols.append(ref("a", v))

    # ── _merge ───────────────────────────────────────────────────────────
    if not nogen and merge_var:
        a_match = re.search(r"\ba\.([A-Za-z_][A-Za-z0-9_]*)", sql_on)
        b_match = re.search(r"\bb\.([A-Za-z_][A-Za-z0-9_]*)", sql_on)
        if a_match and b_match:
            a_ref = ref("a", a_match.group(1))[0]
            b_ref = ref("b", b_match.group(1))[0]
            out_cols.append(
                (
                    "CASE "
                    "WHEN {0} IS NOT NULL AND {1} IS NOT NULL THEN 3 "
                    "WHEN {0} IS NOT NULL THEN 1 "
                    "ELSE 2 "
                    "END".format(a_ref, b_ref),
                    merge_var,
                )
            )

    if not out_cols:
        raise PmergeError("no columns selected")

    # ── 完全同名的输出列加 _1/_2 后缀 ────────────────────────────────────
    used = set()
    final_cols = []
    for expr, name in out_cols:
        base, k = name, 0
        while name in used:
            k += 1
            name = "{}_{}".format(base, k)
        used.add(name)
        final_cols.append((expr, name))

    # ── 仅大小写不同的输出列 DuckDB 一样会改名，                          ──
    # ── 只能先用占位名写出，由 ado 端在 pq use 之后 rename 回真实变量名   ──
    name_cnt = Counter(n.lower() for _, n in final_cols)
    seen_lower = set()
    select_parts, ren_from, ren_to = [], [], []
    for i, (expr, name) in enumerate(final_cols):
        low = name.lower()
        if name_cnt[low] > 1 and low in seen_lower:
            holder = "__pm_o{}".format(i)
            select_parts.append("{} AS {}".format(expr, q(holder)))
            ren_from.append(holder)
            ren_to.append(name)
        else:
            select_parts.append("{} AS {}".format(expr, q(name)))
        seen_lower.add(low)

    def from_clause(path, side):
        cols, handles, _ = sides[side]
        src = "read_parquet('{}') AS {}".format(path, side)
        if handles != cols:
            src += "({})".format(", ".join(q(h) for h in handles))
        return src

    where_sql = ""
    if where_clause and where_clause.strip():
        where_sql = "\n        WHERE {}".format(rewrite(where_clause))

    # ── 报告冲突列（完全同名才算冲突，lev/LEV 在 Stata 里是两个变量）──
    dups = [c for c in using_cols if c in master_cols and c not in case_aliases]
    if dups:
        print(
            "note: using-side duplicate columns renamed with _1 suffix: "
            + ", ".join(sorted(dups))
        )

    select_cols = ",\n        ".join(select_parts)
    sql = f"""
    COPY (
        SELECT {select_cols}
        FROM {from_clause(master_pq, 'a')}
        {jointype} JOIN {from_clause(using_pq, 'b')}
          ON {rewrite(sql_on)}{where_sql}
    ) TO '{output_pq}' (FORMAT 'parquet')
"""
    return sql, ren_from, ren_to


con = duckdb.connect()
Macro.setLocal("pm_error", "")
Macro.setLocal("pm_ren_from", "")
Macro.setLocal("pm_ren_to", "")

try:
    sql, ren_from, ren_to = build(con)
except PmergeError as err:
    # 交给 ado 端用 Stata 的方式报错，而不是甩一段 Python traceback
    Macro.setLocal("pm_error", str(err))
else:
    Macro.setLocal("pm_ren_from", " ".join(ren_from))
    Macro.setLocal("pm_ren_to", " ".join(ren_to))
    print(sql)
    con.execute(sql)

con.close()
