import duckdb, re
from sfi import Macro

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

con = duckdb.connect()

# ── 获取两表列名，检测冲突 ──
master_cols = [r[0] for r in con.execute(
    f"DESCRIBE SELECT * FROM read_parquet('{master_pq}')"
).fetchall()]
using_cols = [r[0] for r in con.execute(
    f"DESCRIBE SELECT * FROM read_parquet('{using_pq}')"
).fetchall()]

# 大小写不敏感的冲突检测
master_cols_lower = {c.lower(): c for c in master_cols}
using_cols_lower = {c.lower(): c for c in using_cols}
dup_cols_lower = set(master_cols_lower.keys()) & set(using_cols_lower.keys())
# 用于快速查找
dup_lookup = dup_cols_lower

# 收集 keepcase 中已处理的别名（小写存储）
case_aliases = set()
if keepcase_vars and keepcase_vars.strip():
    for group in keepcase_vars.split("|"):
        parts = group.split()
        if len(parts) == 3:
            case_aliases.add(parts[2].lower())
        elif len(parts) == 2:
            case_aliases.add(parts[0].split(".")[-1].lower())

# ── 处理 keepusing ──
# 规则：master 列保持原名，using 同名列加 _1 后缀
keep_cols = ""
if keepusing_vars and keepusing_vars.strip():
    if keepusing_vars.strip() == "*":
        a_cols = []
        for c in master_cols:
            if c.lower() in case_aliases:
                continue
            a_cols.append(f"a.{c}")
        b_cols = []
        for c in using_cols:
            if c.lower() in case_aliases:
                continue
            if c.lower() in dup_lookup:
                b_cols.append(f"b.{c} AS {c}_1")
            else:
                b_cols.append(f"b.{c}")
        keep_cols = ", ".join(a_cols + b_cols)
    else:
        cols = []
        for v in keepusing_vars.split():
            if "." in v:
                prefix, col = v.split(".", 1)
                if col == "*":
                    src_cols = master_cols if prefix == "a" else using_cols
                    for c in src_cols:
                        if c.lower() in case_aliases:
                            continue
                        if prefix == "b" and c.lower() in dup_lookup:
                            cols.append(f"b.{c} AS {c}_1")
                        else:
                            cols.append(f"{prefix}.{c}")
                else:
                    cols.append(v)
            else:
                cols.append(f"b.{v}")
        keep_cols = ", ".join(cols)

# ── 处理 keepcase ──
case_cols = ""
if keepcase_vars and keepcase_vars.strip():
    cases = []
    groups = keepcase_vars.split("|")
    for group in groups:
        parts = group.split()
        if len(parts) == 3:
            a_col, b_col, alias = parts
            cases.append(
                f"CASE WHEN {a_col} IS NOT NULL THEN {a_col} ELSE {b_col} END AS {alias}"
            )
        elif len(parts) == 2:
            a_col, b_col = parts
            alias = a_col.split(".")[-1]
            cases.append(
                f"CASE WHEN {a_col} IS NOT NULL THEN {a_col} ELSE {b_col} END AS {alias}"
            )
    if cases:
        case_cols = ",\n        ".join(cases)

# ── 处理 _merge ──
merge_col = ""
if not nogen and merge_var:
    a_match = re.search(r'\ba\.(\w+)', sql_on)
    b_match = re.search(r'\bb\.(\w+)', sql_on)
    if a_match and b_match:
        a_ref = f"a.{a_match.group(1)}"
        b_ref = f"b.{b_match.group(1)}"
        merge_col = (
            f"CASE "
            f"WHEN {a_ref} IS NOT NULL AND {b_ref} IS NOT NULL THEN 3 "
            f"WHEN {a_ref} IS NOT NULL THEN 1 "
            f"ELSE 2 "
            f"END AS {merge_var}"
        )

# ── 处理 WHERE ──
where_sql = ""
if where_clause and where_clause.strip():
    where_sql = f"\n        WHERE {where_clause}"

# ── 拼接 SELECT ──
select_parts = [p for p in [case_cols, keep_cols, merge_col] if p]
select_cols = ",\n        ".join(select_parts)

# ── 报告冲突列 ──
renamed_dups = {using_cols_lower[k] for k in dup_lookup if k not in case_aliases}
if renamed_dups:
    print(f"note: using-side duplicate columns renamed with _1 suffix: {', '.join(sorted(renamed_dups))}")

sql = f"""
    COPY (
        SELECT {select_cols}
        FROM read_parquet('{master_pq}') AS a
        {jointype} JOIN read_parquet('{using_pq}') AS b
          ON {sql_on}{where_sql}
    ) TO '{output_pq}' (FORMAT 'parquet')
"""

print(sql)

con.execute(sql)
con.close()