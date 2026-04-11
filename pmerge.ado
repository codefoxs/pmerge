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
    qui pq save "./.pmerge_parquet/master.parquet", replace
    
    if "`jointype'" == "" local jointype "FULL"
    
    * 获取文件扩展名（取最后一个点之后的内容）
    local using_clean = subinstr("`using'", "\", "/", .)
    local fname = substr("`using_clean'", strpos("`using_clean'", "/") + 1, .)
    * 逐层剥离目录，取最终文件名
    while strpos("`fname'", "/") > 0 {
        local fname = substr("`fname'", strpos("`fname'", "/") + 1, .)
    }
    * 从文件名中取最后一个点之后的扩展名
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
    
    python script "D:/code/Github/pmerge/pmerge.py"
    
    pq use "`output_pq'", clear
    
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
