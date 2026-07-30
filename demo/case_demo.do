* 大小写敏感回归测试
* Stata 里 lev 和 LEV 是两个变量，DuckDB 的标识符却不区分大小写。
* 0.1.3 之前：LEV 会被改名成 LEV_1，而 a.LEV 会静默取到 a.lev 的数据。

clear all
discard
cd "`c(pwd)'"

* master 同时含 lev 和 LEV
clear
set obs 3
gen id  = _n
gen lev = _n*10
gen LEV = _n*100
label var lev "lowercase lev"
label var LEV "UPPERCASE LEV"
save "case_master.dta", replace

clear
set obs 3
gen id  = _n
gen roa = _n/10
save "case_using.dta", replace

* master 只有小写 lev，using 只有大写 LEV
clear
set obs 3
gen id  = _n
gen lev = _n*10
save "case_m_lev.dta", replace

clear
set obs 3
gen id  = _n
gen LEV = _n*1000
save "case_u_upper.dta", replace

* using 端有完全同名的 lev
clear
set obs 3
gen id  = _n
gen lev = _n*7
save "case_u_same.dta", replace


di as txt _n "== 1. keepusing(*)：master 的 lev/LEV 都保留原名 =="
use "case_master.dta", clear
pmerge "a.id=b.id" using "case_using.dta", keepusing(*) nogen
ds
assert lev == id*10
assert LEV == id*100
describe lev LEV
di as res "PASS"

di as txt _n "== 2. 显式引用 a.lev / a.LEV：各取各的列 =="
use "case_master.dta", clear
pmerge "a.id=b.id" using "case_using.dta", keepusing(a.id a.lev a.LEV b.roa) nogen
assert lev == id*10
assert LEV == id*100
di as res "PASS"

di as txt _n "== 3. 跨文件仅大小写不同：不算重名，不加 _1 =="
use "case_m_lev.dta", clear
pmerge "a.id=b.id" using "case_u_upper.dta", keepusing(*) nogen
ds
assert lev == id*10
assert LEV == id*1000
di as res "PASS"

di as txt _n "== 4. 完全同名仍然加 _1 =="
use "case_m_lev.dta", clear
pmerge "a.id=b.id" using "case_u_same.dta", keepusing(*) nogen
ds
assert lev   == id*10
assert lev_1 == id*7
di as res "PASS"

di as txt _n "== 5. keepcase 里混用大小写 =="
use "case_master.dta", clear
pmerge "a.id=b.id" using "case_u_upper.dta", ///
    keepcase("a.id b.id id | a.lev b.LEV lev") keepusing(a.LEV) nogen
assert lev == id*10
assert LEV == id*100
di as res "PASS"

di as txt _n "== 6. 大小写写错但不产生歧义时仍能解析 =="
use "case_m_lev.dta", clear
pmerge "a.id=b.id" using "case_using.dta", keepusing(a.id a.LEV b.roa) nogen
assert lev == id*10
di as res "PASS"

di as txt _n "== 7. 有歧义时报错，而不是随便挑一个 =="
use "case_master.dta", clear
cap noi pmerge "a.id=b.id" using "case_using.dta", keepusing(a.id a.Lev) nogen
assert _rc == 198
di as res "PASS"

di as txt _n "== 8. 变量不存在时报错 =="
use "case_m_lev.dta", clear
cap noi pmerge "a.id=b.id" using "case_using.dta", keepusing(a.id a.nosuchvar) nogen
assert _rc == 198
di as res "PASS"

di as txt _n "== 9. where() 引用大小写冲突列 =="
use "case_master.dta", clear
pmerge "a.id=b.id" using "case_using.dta", keepusing(*) where("a.LEV > 100") nogen
assert LEV > 100
qui count
assert r(N) == 2
di as res "PASS"

di as res _n "ALL CASE-SENSITIVITY TESTS PASSED"
