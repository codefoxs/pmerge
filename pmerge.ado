*! Version 0.1.3 SQL-style merge for Stata, powered by DuckDB.

cap program drop _pmerge_dump_meta
program define _pmerge_dump_meta
    syntax , OUTfile(string) [USINGside CONFlicts(string) LBLConflicts(string) RENames(string)]

    * 用 " a b c " 形式做空格包围的子串匹配
    * 注意：Stata 变量名/值标签名区分大小写（lev 与 LEV 是两个变量），
    * 这里必须精确匹配，不能先 lower()，否则 LEV 会被误判成与 lev 冲突
    local cc " `conflicts' "
    local lc " `lblconflicts' "

    * 解析 renames："from=to|from=to|..."
    local nren 0
    if `"`renames'"' != "" {
        local _r `"`renames'"'
        while `"`_r'"' != "" {
            local _pp = strpos(`"`_r'"', "|")
            if `_pp' > 0 {
                local _one = substr(`"`_r'"', 1, `_pp'-1)
                local _r = substr(`"`_r'"', `_pp'+1, .)
            }
            else {
                local _one `"`_r'"'
                local _r ""
            }
            local _eq = strpos("`_one'", "=")
            if `_eq' > 0 {
                local ++nren
                local rfrom_`nren' = substr("`_one'", 1, `_eq'-1)
                local rto_`nren' = substr("`_one'", `_eq'+1, .)
            }
        }
    }

    * 把所有值标签 dump 到临时 do 文件（label save 自带转义）
    qui label dir
    local _lbl_names `"`r(names)'"'
    local has_lbls 0
    tempfile lbltmp
    if `"`_lbl_names'"' != "" {
        cap qui label save using "`lbltmp'", replace
        if !_rc local has_lbls 1
    }

    tempname h
    qui file open `h' using "`outfile'", write replace text
    file write `h' "* pmerge auto-generated label apply file" _n

    * dataset label 仅 master 端写
    if "`usingside'" == "" {
        local dlbl : data label
        if `"`dlbl'"' != "" {
            file write `h' `"cap label data "`macval(dlbl)'""' _n
        }
    }

    * 重写 label define 行：using 端冲突标签名加 _1
    if `has_lbls' {
        tempname fin
        file open `fin' using "`lbltmp'", read text
        file read `fin' line
        while r(eof) == 0 {
            local stripped = ltrim(`"`macval(line)'"')
            if substr(`"`macval(stripped)'"', 1, 13) == "label define " {
                local body = substr(`"`macval(stripped)'"', 14, .)
                local sp = strpos(`"`macval(body)'"', " ")
                if `sp' > 0 {
                    local lname = substr(`"`macval(body)'"', 1, `sp'-1)
                    local rest_ = substr(`"`macval(body)'"', `sp', .)
                }
                else {
                    local lname `"`macval(body)'"'
                    local rest_ ""
                }
                local lname_out "`lname'"
                if "`usingside'" != "" {
                    if strpos(`"`lc'"', " `lname' ") > 0 {
                        local lname_out "`lname'_1"
                    }
                }
                file write `h' `"cap noi label define `lname_out'`macval(rest_)'"' _n
            }
            else if `"`macval(line)'"' != "" {
                file write `h' `"`macval(line)'"' _n
            }
            file read `fin' line
        }
        file close `fin'
        cap erase "`lbltmp'"
    }

    * 每个变量
    qui ds
    local vars `r(varlist)'
    foreach v of local vars {
        local target "`v'"
        if "`usingside'" != "" {
            if strpos(`"`cc'"', " `v' ") > 0 {
                local target "`v'_1"
            }
        }

        local vlbl : variable label `v'
        local vval : value label `v'
        local vfmt : format `v'

        local vval_out "`vval'"
        if "`usingside'" != "" & "`vval'" != "" {
            if strpos(`"`lc'"', " `vval' ") > 0 {
                local vval_out "`vval'_1"
            }
        }

        if `"`vlbl'"' != "" {
            file write `h' `"cap label variable `target' "`macval(vlbl)'""' _n
        }
        if "`vval_out'" != "" {
            file write `h' `"cap label values `target' `vval_out'"' _n
        }
        if "`vfmt'" != "" {
            file write `h' `"cap format `target' `vfmt'"' _n
        }

        * master 端：keepcase rename 的 alias 也写一份
        if "`usingside'" == "" & `nren' > 0 {
            forvalues i = 1/`nren' {
                if "`rfrom_`i''" == "`v'" {
                    local atgt "`rto_`i''"
                    if "`atgt'" != "`v'" {
                        if `"`vlbl'"' != "" {
                            file write `h' `"cap label variable `atgt' "`macval(vlbl)'""' _n
                        }
                        if "`vval'" != "" {
                            file write `h' `"cap label values `atgt' `vval'"' _n
                        }
                        if "`vfmt'" != "" {
                            file write `h' `"cap format `atgt' `vfmt'"' _n
                        }
                    }
                }
            }
        }
    }

    file close `h'
end


cap program drop pmerge
program define pmerge
    * 处理 pmerge, clear
    gettoken first rest : 0, parse(", ")
    if `"`first'"' == "," {
        gettoken second : rest, parse(" ")
        if "`second'" == "clear" {
            cap erase "./.pmerge_parquet/master.parquet"
            cap erase "./.pmerge_parquet/using.parquet"
            cap erase "./.pmerge_parquet/pmerge_data.parquet"

            * 删除目录下可能残留的其他文件
            local pmerge_dir "./.pmerge_parquet"
            local flist : dir "`pmerge_dir'" files "*"
            foreach f of local flist {
                cap erase "`pmerge_dir'/`f'"
            }

            cap rmdir "./.pmerge_parquet"
            if _rc == 0 {
                di as res "pmerge: temporary files cleaned up"
            }
            else {
                di as err "pmerge: failed to remove .pmerge_parquet directory"
            }
            exit
        }
    }

    syntax anything using/, [KEEPUsing(string) JOINtype(string) KEEPCase(string) ///
        WHERE(string asis) NOGENerate GENerate(name)]

    * 至少需要 keepusing 或 keepcase 之一
    if "`keepusing'" == "" & "`keepcase'" == "" {
        di as err "must specify at least one of keepusing() or keepcase()"
        exit 198
    }

    * nogenerate 和 generate() 不能同时使用
    if "`nogenerate'" != "" & "`generate'" != "" {
        di as err "options nogenerate and generate() may not be combined"
        exit 198
    }

    * 默认生成 _merge 变量名为 _merge
    if "`nogenerate'" == "" & "`generate'" == "" {
        local generate "_merge"
    }

    * 生成 _merge 时强制使用 FULL JOIN
    if "`nogenerate'" == "" {
        if "`jointype'" != "" & upper("`jointype'") != "FULL" {
            di as res "note: generate(_merge) requires FULL JOIN, overriding join(`jointype')"
        }
        local jointype "FULL"
    }

    cap mkdir ".pmerge_parquet"

    * 解析 keepcase 中的 a_col -> alias 映射
    local kc_renames ""
    if `"`keepcase'"' != "" {
        local _kc_rest `"`keepcase'"'
        while `"`_kc_rest'"' != "" {
            local _pp = strpos(`"`_kc_rest'"', "|")
            if `_pp' > 0 {
                local _grp = substr(`"`_kc_rest'"', 1, `_pp'-1)
                local _kc_rest = substr(`"`_kc_rest'"', `_pp'+1, .)
            }
            else {
                local _grp `"`_kc_rest'"'
                local _kc_rest ""
            }
            local _nw : word count `_grp'
            if `_nw' == 3 {
                local _p1 : word 1 of `_grp'
                local _p3 : word 3 of `_grp'
                local _acol "`_p1'"
                if substr("`_acol'", 1, 2) == "a." local _acol = substr("`_acol'", 3, .)
                local kc_renames "`kc_renames'`_acol'=`_p3'|"
            }
            else if `_nw' == 2 {
                local _p1 : word 1 of `_grp'
                local _acol "`_p1'"
                if substr("`_acol'", 1, 2) == "a." local _acol = substr("`_acol'", 3, .)
                local kc_renames "`kc_renames'`_acol'=`_acol'|"
            }
        }
    }

    * 记录 master 列名/值标签名，供 using 端冲突检测（区分大小写）
    qui ds
    local master_cols_l "`r(varlist)'"
    qui label dir
    local master_lbls_l `"`r(names)'"'

    * 清掉旧的 apply 文件
    cap erase "./.pmerge_parquet/master_apply.do"
    cap erase "./.pmerge_parquet/using_apply.do"

    * 捕获 master 元数据
    _pmerge_dump_meta, outfile("./.pmerge_parquet/master_apply.do") renames(`"`kc_renames'"')

    qui pq save "./.pmerge_parquet/master.parquet", replace

    if "`jointype'" == "" local jointype "FULL"

    * 获取文件扩展名
    local using_clean = subinstr("`using'", "\", "/", .)
    local fname = substr("`using_clean'", strpos("`using_clean'", "/") + 1, .)
    while strpos("`fname'", "/") > 0 {
        local fname = substr("`fname'", strpos("`fname'", "/") + 1, .)
    }
    local ext ""
    local tmp "`fname'"
    while strpos("`tmp'", ".") > 0 {
        local ext = substr("`tmp'", strpos("`tmp'", ".") + 1, .)
        local tmp "`ext'"
    }
    local ext = lower("`ext'")

    if "`ext'" == "dta" {
        preserve
        qui use "`using'", clear
        _pmerge_dump_meta, outfile("./.pmerge_parquet/using_apply.do") usingside ///
            conflicts(`"`master_cols_l'"') lblconflicts(`"`master_lbls_l'"')
        qui pq save "./.pmerge_parquet/using.parquet", replace
        restore
        local using_pq "./.pmerge_parquet/using.parquet"
    }
    else if "`ext'" == "sas7bdat" {
        preserve
        qui pq use_sas using "`using'", clear
        qui pq save "./.pmerge_parquet/using.parquet", replace
        restore
        local using_pq "./.pmerge_parquet/using.parquet"
    }
    else if "`ext'" == "sav" {
        preserve
        qui pq use_spss using "`using'", clear
        qui pq save "./.pmerge_parquet/using.parquet", replace
        restore
        local using_pq "./.pmerge_parquet/using.parquet"
    }
    else if "`ext'" == "csv" {
        preserve
        qui pq use_csv using "`using'", clear
        qui pq save "./.pmerge_parquet/using.parquet", replace
        restore
        local using_pq "./.pmerge_parquet/using.parquet"
    }
    else if "`ext'" == "parquet" {
        local using_pq "`using'"
    }
    else {
        di as err "unsupported file format: .`ext'"
        di as err "supported formats: .dta .parquet .sas7bdat .sav .csv"
        exit 198
    }

    * 统一路径为正斜杠
    local master_pq = subinstr("./.pmerge_parquet/master.parquet", "\", "/", .)
    local using_pq = subinstr("`using_pq'", "\", "/", .)
    local output_pq = subinstr("./.pmerge_parquet/pmerge_data.parquet", "\", "/", .)

    local sql_on `anything'
    local keepusing_vars `keepusing'
    local keepcase_vars `keepcase'
    local where_clause `where'
    local merge_var `generate'
    local nogen `nogenerate'
    
    //qui findfile pmerge.ado
    //local precmdurl = ustrregexra(r(fn),"/pmerge.ado","")
    //local cmdurl "`=ustrregexra("`precmdurl'","\\","/")'"
    
    //python script "`cmdurl'/pmerge.py"
    python script "`c(sysdir_plus)'/py/pmerge.py"

    * Python 端的用法错误（列名找不到/有歧义等）在这里按 Stata 的方式报出来
    if `"`pm_error'"' != "" {
        di as err `"pmerge: `pm_error'"'
        exit 198
    }

    pq use "`output_pq'", clear

    * DuckDB 标识符不区分大小写，仅大小写不同的输出列（如 lev/LEV）
    * 只能先以占位名写出，读回来后再改回真实变量名
    if "`pm_ren_from'" != "" {
        local _n : word count `pm_ren_from'
        forvalues i = 1/`_n' {
            local _f : word `i' of `pm_ren_from'
            local _t : word `i' of `pm_ren_to'
            rename `_f' `_t'
        }
    }

    * 还原 dta→parquet 过程中丢失的标签
    cap qui do "./.pmerge_parquet/master_apply.do"
    cap qui do "./.pmerge_parquet/using_apply.do"

    * 报告 _merge 结果
    if "`nogen'" == "" {
        di as txt ""
        di as txt "    Result                      Number of obs"
        di as txt "    -----------------------------------------"
        qui count if `merge_var' == 1
        di as txt "    Not matched (master only)    " as res %12.0fc r(N)
        qui count if `merge_var' == 2
        di as txt "    Not matched (using only)     " as res %12.0fc r(N)
        qui count if `merge_var' == 3
        di as txt "    Matched                      " as res %12.0fc r(N)
        di as txt "    -----------------------------------------"
        qui count
        di as txt "    Total                        " as res %12.0fc r(N)

        label define _m_lbl 1 "master only" 2 "using only" 3 "matched", replace
        label values `merge_var' _m_lbl
    }
end
