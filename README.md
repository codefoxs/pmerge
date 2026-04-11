# pmerge

SQL-style merge for Stata, powered by DuckDB.

Perform non-equi joins, range matching, and cross-format merges directly in Stata using SQL syntax.

## Why pmerge?

Stata's native `merge` only supports equi-joins. Common research tasks like CRSP-Compustat linking require range matching (`a.datadate >= b.linkdt AND a.datadate <= b.linkenddt`), which forces awkward workarounds with `joinby` + `keep if`. **pmerge** brings SQL JOIN syntax into Stata, making these operations simple and fast.

+ **SQL JOIN syntax** — LEFT, RIGHT, INNER, FULL, CROSS joins with arbitrary ON conditions
+ **Non-equi joins** — range matching, inequality conditions, date interval lookups
+ **Cross-format** — merge across .dta, .parquet, .sas7bdat, .sav, .csv files (highly recommend parquet!)
+ **Familiar output** — generates `_merge` indicator (1/2/3) just like native `merge`
+ **Automatic conflict resolution** — duplicate column names handled with `_1` suffix on using-side

## Requirements

+ Stata 16.0+
+ Python 3.8+ with `duckdb` and `pandas` (`pip install duckdb pandas`)
+ [`pq`](https://github.com/mdroste/stata-pq) command installed

## Install

```stata
* Latest version
cap ado uninstall pmerge
net install pmerge, from("https://raw.githubusercontent.com/codefoxs/pmerge/main/") replace

* Old versions
cap ado uninstall pmerge
net install pmerge, from("https://raw.githubusercontent.com/codefoxs/pmerge/v#.#.#/") replace
```

Make sure Python is configured in Stata:

```stata
set python_exec "D:/Python311/python.exe", permanently
```

Make sure `pq` is installed in Stata:

```stata
ssc install pq, replace
```

Make sure `duckdb` has installed `read_stat`:

```python
import duckdb
con = duckdb.connect()
con.execute("INSTALL read_stat FROM community")
con.close()
```

## Syntax

```stata
pmerge "ON_condition" using filename , [options]

pmerge , clear
```

| Option               | Description                                                  |
| -------------------- | ------------------------------------------------------------ |
| `keepusing(varlist)` | Variables to keep. `*` = all, `a.*` = master all, `b.*` = using all |
| `keepcase(spec)`     | CASE WHEN for key columns. Format: `a.col b.col alias | ...` |
| `jointype(type)`     | LEFT / RIGHT / INNER / FULL / CROSS. Default: FULL           |
| `where(condition)`   | SQL WHERE filter applied after JOIN                          |
| `nogenerate`         | Suppress `_merge` variable                                   |
| `generate(varname)`  | Custom name for merge indicator. Default: `_merge`           |
| `clear`              | Delete temporary files in `.pmerge_parquet/`                 |

## Examples

### Basic equi-join

```stata
use master, clear
pmerge "a.id=b.id" using "supplement.dta", keepusing(x1 x2)
```

### Range matching (CRSP-Compustat Link Table)

```stata
use compustat, clear
pmerge "a.gvkey=b.gvkey AND a.datadate>=b.linkdt AND (a.datadate<=b.linkenddt OR b.linkenddt IS NULL)" ///
    using "ccm_link.parquet", ///
    keepusing(permno permco) nogen join(LEFT)
```

### FULL JOIN with keepcase

When using FULL JOIN, key columns may be null on one side. `keepcase` resolves this by keeping the non-null value:

```stata
use master, clear
pmerge "a.stkcd=b.stkcd AND a.year=b.year" using "WW.dta", ///
    keepusing(a.sa b.ww) join(FULL) ///
    keepcase(a.stkcd b.stkcd stkcd | a.year b.year year)
```

### WHERE filter

```stata
use master, clear
pmerge "a.stkcd=b.stkcd AND a.year=b.year" using "SA.parquet", ///
    keepusing(sa) nogen join(LEFT) ///
    where(a.year >= 2010)
```

### Cross-format merge (SAS file)

```stata
use master, clear
pmerge "a.gvkey=b.gvkey AND a.fyear=b.fyear" using "compustat.sas7bdat", ///
    keepusing(at sale) nogen join(LEFT)
```

### Clean up temporary files

```stata
pmerge, clear
```

## How it works

1. Stata saves the current dataset (master) as a temporary Parquet file
2. The using file is converted to Parquet if needed (.dta, .sas7bdat, .sav, .csv)
3. A Python script constructs and executes a SQL query via DuckDB
4. The result is saved as Parquet and loaded back into Stata via `pq`

## Merge indicator

By default, `pmerge` generates a `_merge` variable (forces FULL JOIN):

```
    Result                      Number of obs
    -----------------------------------------
    Not matched (master only)           1,234
    Not matched (using only)              567
    Matched                            45,678
    -----------------------------------------
    Total                              47,479
```

| Value | Label       | Description                   |
| ----- | ----------- | ----------------------------- |
| 1     | master only | Observation from master only  |
| 2     | using only  | Observation from using only   |
| 3     | matched     | Observation matched from both |

Use `nogenerate` to suppress, or `generate(varname)` to customize the variable name.

## Duplicate column names

When master and using share column names, master columns keep their original names and using-side duplicates are automatically renamed with a `_1` suffix. Columns handled by `keepcase` are excluded from renaming.

```
note: using-side duplicate columns renamed with _1 suffix: gvkey, year
```

## Author

1. 公众号：凯恩斯学计量
2. Claude Opus 4.6