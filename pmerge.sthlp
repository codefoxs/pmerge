{smcl}
{* *! version 0.1.1 11Apr2026}{...}
{vieweralsosee "[R] merge" "help merge"}{...}
{vieweralsosee "[R] joinby" "help joinby"}{...}
{vieweralsosee "[R] pq" "help pq"}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "pmerge##syntax"}{...}
{viewerjumpto "Description" "pmerge##description"}{...}
{viewerjumpto "Options" "pmerge##options"}{...}
{viewerjumpto "Supported formats" "pmerge##formats"}{...}
{viewerjumpto "Examples" "pmerge##examples"}{...}
{viewerjumpto "Requirements" "pmerge##requirements"}{...}
{viewerjumpto "Author" "pmerge##author"}{...}
{title:Title}

{p2colset 5 15 15 2}{...}
{p2col :{hi:pmerge} {hline 2}}SQL-style merge powered by DuckDB (requires {help pq} and Python){p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 14 4}{cmd:pmerge} {it:"ON_condition"} {cmd:using} {it:filename} , [{it:options}]

{p 8 14 4}{cmd:pmerge} , {opt clear}

{synoptset 45 tabbed}{...}
{synopthdr}
{synoptline}
{syntab: Main (at least one required)}
{synopt: {opt keepu:sing(varlist)}}Variables to keep from the using file. Use {bf:*} for all variables, {bf:a.*} for all master variables, {bf:b.*} for all using variables, or specify individual variables like {bf:b.var1 b.var2}. Variables without a prefix are assumed from the using table (b.){p_end}

{synopt: {opt keepc:ase(case_spec)}}Generate CASE WHEN columns for key variables. Format: {bf:a.col b.col alias}, separated by {bf:|} for multiple columns. Keeps the non-null value from either table, useful for FULL JOIN key columns{p_end}

{syntab: Join}
{synopt: {opt join:type(type)}}Type of SQL JOIN. Accepts {bf:LEFT}, {bf:RIGHT}, {bf:INNER}, {bf:FULL}, or {bf:CROSS}. Default is {bf:FULL} when generating _merge, otherwise {bf:LEFT}{p_end}

{syntab: Filter}
{synopt: {opt where(condition)}}SQL WHERE clause applied after the JOIN. Uses SQL syntax with {bf:a.} and {bf:b.} prefixes{p_end}

{syntab: Merge indicator}
{synopt: {opt nogen:erate}}Do not generate the merge indicator variable{p_end}
{synopt: {opt gen:erate(varname)}}Name of the merge indicator variable. Default is {bf:_merge}. Values: 1 = master only, 2 = using only, 3 = matched. When specified, JOIN type is forced to FULL{p_end}

{syntab: Cleanup}
{synopt: {opt clear}}Delete all temporary files in {bf:.pmerge_parquet/} directory. Use as {cmd:pmerge, clear}{p_end}
{synoptline}
{p2colreset}{...}

{marker description}{...}
{title:Description}

{pstd}{cmd:pmerge} performs SQL-style JOIN operations on the current dataset (master) and an external file (using), powered by DuckDB via Python. Unlike Stata's native {cmd:merge}, it supports:{p_end}

{pstd}1. Non-equi joins (inequality conditions, range matching, e.g., {it:a.date >= b.linkdt AND a.date <= b.linkenddt}){p_end}
{pstd}2. Multiple file formats as input (.dta, .parquet, .sas7bdat, .sav, .csv){p_end}
{pstd}3. SQL WHERE filtering applied during the merge{p_end}
{pstd}4. CASE WHEN logic for resolving key columns in FULL JOINs{p_end}

{pstd}The ON condition uses SQL syntax with {bf:a.} referring to the master dataset and {bf:b.} referring to the using file. Multiple conditions are connected with {bf:AND}.{p_end}

{pstd}When two tables share column names, master columns keep their original names and using-side duplicates are automatically renamed with a {bf:_1} suffix.{p_end}

{marker options}{...}
{title:Options}

{dlgtab:Main}

{phang}{opt keepusing(varlist)} specifies which variables to retain in the merged result. At least one of {opt keepusing()} or {opt keepcase()} must be specified.{p_end}

{pmore}Use {bf:*} to keep all variables from both tables. Use {bf:a.*} or {bf:b.*} to keep all variables from master or using respectively. Specify individual variables with or without table prefix: {bf:b.ww} or simply {bf:ww} (defaults to using table).{p_end}

{phang}{opt keepcase(case_spec)} generates CASE WHEN expressions for specified columns. Each group has the format {bf:a.col b.col alias} (or {bf:a.col b.col} where alias defaults to the master column name). Multiple groups are separated by {bf:|}.{p_end}

{pmore}This is useful in FULL JOINs where key columns may be null on one side. The generated SQL is: {bf:CASE WHEN a.col IS NOT NULL THEN a.col ELSE b.col END AS alias}.{p_end}

{dlgtab:Join}

{phang}{opt jointype(type)} specifies the SQL JOIN type. Options are {bf:LEFT} (keep all master rows), {bf:RIGHT} (keep all using rows), {bf:INNER} (keep only matched rows), {bf:FULL} (keep all rows from both), or {bf:CROSS} (cartesian product).{p_end}

{pmore}When a merge indicator is generated (default behavior), the JOIN type is forced to {bf:FULL} regardless of this option.{p_end}

{dlgtab:Filter}

{phang}{opt where(condition)} applies a SQL WHERE clause after the JOIN. Use {bf:a.} and {bf:b.} prefixes to reference columns. Example: {bf:where(a.year >= 2010 AND b.ww IS NOT NULL)}.{p_end}

{dlgtab:Merge indicator}

{phang}{opt nogenerate} suppresses creation of the merge indicator variable.{p_end}

{phang}{opt generate(varname)} specifies the name of the merge indicator variable. Default is {bf:_merge}. The variable takes values 1 (master only), 2 (using only), or 3 (matched), with value labels attached automatically.{p_end}

{marker formats}{...}
{title:Supported file formats}

{pstd}The {cmd:using} file can be any of the following formats:{p_end}

{pstd}{bf:.parquet} {hline 2} Apache Parquet (used directly by DuckDB, fastest){p_end}
{pstd}{bf:.dta} {hline 2} Stata dataset (converted via {cmd:pq save}){p_end}
{pstd}{bf:.sas7bdat} {hline 2} SAS dataset (converted via {cmd:pq use_sas}){p_end}
{pstd}{bf:.sav} {hline 2} SPSS dataset (converted via {cmd:pq use_spss}){p_end}
{pstd}{bf:.csv} {hline 2} Comma-separated values (converted via {cmd:pq use_csv}){p_end}

{marker examples}{...}
{title:Examples}
{hline}

{pstd}{bf:Basic merge (equi-join)}{p_end}
{phang2}{cmd:. sysuse auto, clear}{p_end}
{phang2}{cmd:. pmerge "a.make=b.make" using "prices.dta", keepusing(price_new)}{p_end}

{pstd}{bf:Range matching (CRSP-Compustat link table)}{p_end}
{phang2}{cmd:. use compustat, clear}{p_end}
{phang2}{cmd:. pmerge "a.gvkey=b.gvkey AND a.datadate>=b.linkdt AND (a.datadate<=b.linkenddt OR b.linkenddt IS NULL)" using "ccm_link.parquet", keepusing(permno permco) nogen join(LEFT)}{p_end}

{pstd}{bf:FULL JOIN with keepcase for key columns}{p_end}
{phang2}{cmd:. use master, clear}{p_end}
{phang2}{cmd:. pmerge "a.stkcd=b.stkcd AND a.year=b.year" using "WW.dta", keepusing(a.sa b.ww) join(FULL) keepcase(a.stkcd b.stkcd stkcd | a.year b.year year)}{p_end}

{pstd}{bf:With WHERE filter}{p_end}
{phang2}{cmd:. use master, clear}{p_end}
{phang2}{cmd:. pmerge "a.stkcd=b.stkcd AND a.year=b.year" using "SA.parquet", keepusing(sa) nogen join(LEFT) where(a.year >= 2010)}{p_end}

{pstd}{bf:Keep all variables from both tables}{p_end}
{phang2}{cmd:. use master, clear}{p_end}
{phang2}{cmd:. pmerge "a.gvkey=b.gvkey AND a.fyear=b.fyear" using "annual.parquet", keepusing(*) nogen join(INNER)}{p_end}

{pstd}{bf:Custom merge indicator name}{p_end}
{phang2}{cmd:. use master, clear}{p_end}
{phang2}{cmd:. pmerge "a.id=b.id" using "supplement.dta", keepusing(x1 x2) gen(merge_supp)}{p_end}

{pstd}{bf:Cross-format merge (SAS file)}{p_end}
{phang2}{cmd:. use master, clear}{p_end}
{phang2}{cmd:. pmerge "a.gvkey=b.gvkey AND a.fyear=b.fyear" using "compustat.sas7bdat", keepusing(at sale) nogen join(LEFT)}{p_end}

{pstd}{bf:Clean up temporary files}{p_end}
{phang2}{cmd:. pmerge, clear}{p_end}
{hline}

{marker requirements}{...}
{title:Requirements}

{pstd}1. Stata 16.0 or later (Python integration required){p_end}
{pstd}2. Python 3.8+ with {bf:duckdb} and {bf:pandas} packages installed{p_end}
{pstd}3. {cmd:pq} command installed ({browse "https://github.com/mdroste/stata-pq":github.com/mdroste/stata-pq}){p_end}
{pstd}4. Python path configured in Stata: {cmd:set python_exec "path/to/python.exe", permanently}{p_end}

{marker author}{...}
{title:Author}

{pstd}1. 公众号：凯恩斯学计量{p_end}
{pstd}2. Claude Opus 4.6{p_end}

{phang}{p_end}
