cd "D:\code\Github\pmerge\demo"

use "master.dta", clear

pmerge "a.stkcd=b.code AND a.year=b.time" using "using.dta", keepusing(*)


use "master.dta", clear

pmerge "a.stkcd=b.code AND a.year=b.time" using "using.dta", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x2)


use "master.dta", clear

pmerge "a.stkcd=b.code AND a.year=b.time" using "using.dta", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x2) join(LEFT) nogen

use "master.dta", clear

pmerge "a.stkcd=b.code AND a.year=b.time AND a.year <= 2002" using "using.dta", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x2)

use "using.dta", clear
export spss using "using.sav", replace

use "master.dta", clear

pmerge "a.stkcd=b.code AND a.year=b.time" using "using.sav", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x2)


use "master.dta", clear

pmerge "a.stkcd=b.stkcd AND a.year>=b.syear AND a.year<=b.eyear" using "usingname.dta", ///
        keepcase("a.stkcd b.stkcd stkcd") ///
        keepusing(a.year a.x1 b.name)

use "master.dta", clear
label var x1 "xx1"
save "master2.dta", replace
use "using.dta", clear
label var x2 "xx2"
gen x1 = x2
label var x1 "xxx1"
save "using2.dta", replace

discard
use "master2.dta", clear
pmerge "a.stkcd=b.code AND a.year=b.time" using "using2.dta", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x1 b.x2)

use "master2.dta", clear
pmerge "a.stkcd=b.code AND a.year=b.time" using "using2.dta", ///
        keepcase("a.stkcd b.code stkcd | a.year b.time year") ///
        keepusing(a.x1 b.x2) join(LEFT) nogen
