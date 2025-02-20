* _eventiv.ado 1.00 Aug 24 2021

version 11.2

cap program drop _eventiv
program define _eventiv, rclass
	#d;
	syntax varlist(fv ts numeric) [aw fw pw] [if] [in], /* Covariates go in varlist. Can add fv ts later */
	panelvar(varname) /* Panel variable */
	timevar(varname) /* Time variable */
	policyvar(varname) /* Policy variable */
	lwindow(integer) /* Estimation window. Need to set a default, but it has to be based on the dataset */
	rwindow(integer)
	proxy (varlist numeric) /* Proxy variable(s) */
	[
	proxyiv(string) /* Instruments. Either numlist with lags or varlist with names of instrumental variables */
	nofe /* No fixed effects */
	note /* No time effects */
	savek(string) /* Generate the time-to-event dummies, trend and keep them in the dataset */	
	nogen /* Do not generate k variables */
	kvars(string) /* Stub for event dummies to include, if they have been generated already */		
	norm(integer -1) /* Normalization */	
	reghdfe /* Use reghdfe for estimation */	
	nostaggered /* Calculate endpoints without absorbing policy assumption, requires z */
	absorb(string) /* Absorb additional variables in reghdfe */ 
	*
	]
	;
	#d cr
	
	marksample touse
	
	tempname delta Vdelta bb VV bb2 VV2 delta2 Vdelta2 deltaov Vdeltaov deltax Vdeltax deltaxsc bby bbx VVy VVx 
	* bb delta coefficients
	* VV variance of delta coefficients
	* bb2 delta coefficients for overlay plot
	* VV2 variance of delta coefficients for overlay plot
	* delta2 included cefficientes in overlaty plot
	* VVdelta2 variance of included delta coefficients in overlay plot
	
	loc i = "`panelvar'"
	loc t = "`timevar'"
	loc z = "`policyvar'"
	
	loc leads : word count `proxy'
	if "`proxyiv'"=="" & `leads'==1 loc proxyiv "select"
	
	* If proxy specified but no proxyiv, assume numlist for leads of policyvar
	if "`proxyiv'"=="" {
		di as text _n "No proxy instruments specified. Using leads of differenced policy variables as instruments."
		loc leads : word count `proxy'		
		forv j=1(1)`leads' {
			loc proxyiv "`proxyiv' `j'"
		}
	}
	
	* IV selection if proxyiv = selection
	else if "`proxyiv'"=="select" {
		* Only for one proxy case 		
		if `leads'>1 {
			di as err "Proxy instrument selection only available for the one proxy - one instrument case"
			exit 301
		}
		else {
			di as text _n "proxyiv=select. Selecting lead order of differenced policy variable to use as instrument."
			loc Fstart = 0
			forv v=1(1)`=-`lwindow'' {
				tempvar _fd`v'`z'
				qui gen double `_fd`v'`z'' = f`v'.d.`z' if `touse'
				qui reg `proxy' `_fd`v'`z'' if `touse'
				loc Floop = e(F)
				if `Floop' > `Fstart' {
					loc Fstart = `Floop'
					loc proxyiv "`v'"				
				}			
			}
			di as text _n "Lead `proxyiv' selected."
		}
		
	}
		
	
	* Parse proxyiv and generate leads if neccesary
	loc rc=0
	loc ivwords = 0
	foreach v in `proxyiv' {
		cap confirm integer number `v'
		if _rc loc ++rc
		loc ++ivwords
	}
	* Three possible types of lists: all numbers for leads, all vars for external instruments, or mixed
	* All numbers
	if `rc' == 0 {
		loc leadivs ""
		foreach v in `proxyiv' {
			qui gen double _fd`v'`z' = f`v'.d.`z' if `touse'
			loc leadivs "`leadivs' _fd`v'`z'"
		}
		loc instype = "numlist"		
		loc varivs = ""
	}
	* All words
	else if `rc'==`ivwords' {
		foreach v in `proxyiv' {
			confirm numeric variable `v'
		}
		loc instype = "varlist"
		loc leadivs = "" 
		loc varivs = "`proxyiv'"
	}
	* Mixed
	else {
		loc leadivs ""
		loc varivs ""
		foreach v in `proxyiv' {
			cap confirm integer number `v'
			if _rc loc varivs "`varivs' `v'"
			else {
				qui gen double_fd`v'`z' = f`v'.d.`z' if `touse'
				loc leadivs "`leadivs' _fd`v'`z'"
			}
		}
		
		loc instype "mixed"
	}	
		
	* Count normalizations and set omitted coefs for plot accordingly
	* Need one more normalization per IV
	
	loc komit ""
	loc norm0 "`norm'"
	
	* Set normalizations in case these are numbers, so we are using leads of delta z
	loc ivnorm ""
	if "`instype'"=="numlist" | "`instype'"=="mixed" {
		foreach v in `proxyiv' {
			cap confirm integer number `v'
			if !_rc {
				if (`v'==1 | `v'==2) & `norm'==-1 loc ivnorm "`ivnorm' -2"				
				else loc ivnorm "`ivnorm' -`v'"		
			}
			else {
				di as err "Lead of policy variable to be used as instrument must be an integer."
				exit 301
			}
		}
	}
	
	* Normalize one more lag if normalization = number of proxys
	if "`instype'"=="numlist" | "`instype'"=="mixed" {
		loc np: word count `proxy' 
		* loc npiv: word count `norm' `ivnorm'
		loc npiv : list norm | ivnorm
		loc npiv : list uniq npiv
		loc npiv : word count `npiv'
		if `np'==`npiv' {
			loc ivnormcomma : subinstr local ivnorm " " ",", all
			loc ivmin = min(`ivnormcomma')
			loc ivnorm "`ivnorm' `=`ivmin'-1'"
		}
	}
		
	* No need to normalize for external instruments. If the user generates a lead of z and uses it as a variable, the instrument is collinear.
	
	foreach j in `norm' `ivnorm' {
		loc norm "`norm' `j' "
		loc komit "`komit' `j'"
	}
	loc komit: list uniq komit		
	
	if "`gen'" != "nogen" {	
		_eventgenvars if `touse', panelvar(`panelvar') timevar(`timevar') policyvar(`policyvar') lwindow(`lwindow') rwindow(`rwindow') `trend' norm(`norm') `staggered'
		loc included=r(included)
		loc names=r(names)	
		loc komittrend=r(komittrend)
		if "`komittrend'"=="." loc komittrend = ""
	}
	else {
		loc kvstub "`kvars'"		
		loc j=1
		loc names ""
		loc included ""
		foreach var of varlist `kvstub'* {	
			if `norm' < 0 loc kvomit = "m`=abs(`norm')'"
			else loc kvomit "p`=abs(`norm')'"
			if "`var'"=="`kvstub'_evtime" | "`var'" == "`kvstub'_eq_`kvomit'" continue	
			if "`kvstub'"!="_k" {
				loc sub : subinstr local var "`kvstub'" "_k", all
				clonevar `sub' = `var'
			}
			else {
				loc sub = "`var'"
			}
			if `j'==1 loc names `""`sub'""'
			else loc names `"`names'.."`sub'""'
			* "
			loc included "`included' `sub'"
			loc ++ j			
		}		
		loc komittrend=r(komittrend)
		if "`komittrend'"=="." loc komittrend = ""	
	}		
	*"
	loc komit "`norm' `komittrend'"
	loc komit = strtrim(stritrim("`komit'"))
	loc komit: list uniq komit	
	
	* Check that the iv normalization works
	
	foreach v in `leadivs' `varivs' {
		qui _regress `v' `included' [`weight'`exp'] if `touse', absorb(`i')
		if e(r2)==1 {
			di as err "Instrument is collinear with the included event-time dummies. You may have generated leads of the policy variable and included them in the proxyiv option instead of specifying the lead numbers."
			exit 301
		}	
	}
	
	if "`te'" == "note" loc tte ""
	else loc tte "i.`t'"
	
	* Main regression
	if "`reghdfe'"=="" {
		
		if "`fe'" == "nofe" {
			loc cmd "ivregress 2sls"
			loc ffe ""
			loc small "small"
		}
		else {
			loc cmd "xtivreg"
			loc ffe "fe"
		}
		`cmd' `varlist' (`proxy' = `leadivs' `varivs') `included' `tte' [`weight'`exp'] if `touse' , `ffe' `small' `options'		
	}
	else {
		loc cmd "reghdfe"
		if "`fe'" == "nofe" & "`te'"=="" & "`absorb'"=="" {						
			loc noabsorb "noabsorb"
			loc abs ""
		}
		else if "`fe'" == "nofe" & "`te'"=="" & "`absorb'"!="" {						
			loc noabsorb "noabsorb"
			loc abs "absorb(`absorb')"
		}
		else if "`fe'" == "nofe" & "`te'"!=""{
			loc abs "absorb(`te' `absorb')"	
			loc noabsorb ""
		}
		else if "`fe'" != "nofe" & "`te'"==""{
			loc abs "absorb(`i' `absorb')"	
			loc noabsorb ""
		}
		else {
			loc abs "absorb(`i' `te' `absorb')"	
			loc noabsorb ""
		}
		ivreghdfe `varlist' (`proxy' = `leadivs' `varivs') `included' [`weight'`exp'] if `touse', `absorb' `noabsorb' `options'
	}
	
	* Return coefficients and variance matrix of the delta k estimates separately
	mat `bb'=e(b)
	mat `VV'=e(V)
	
	mat `delta' = `bb'[1,`names']
	mat `Vdelta' = `VV'[`names',`names']
		
	if "`reghdfe'"=="" {
		if "`fe'" == "nofe" {
			loc df=e(df_r)
		}
		else {
			loc df=e(df_rz)
		}
	}
	else {
		loc df=e(df_r)
		if `df'==. loc df=e(Fdf2)
	}
	
	
	loc kmax=`=`rwindow'+1'
	loc kmin=`=`lwindow'-1'
	
	tempvar esample
	gen byte `esample' = e(sample)
	
	
	* Plots	
	
	* Calculate mean before change in policy for 2nd axis in plot
	* This needs to be relative to normalization
	loc absnorm=abs(`norm0')
	
	
	
	tokenize `varlist'
	qui su `1' if f`absnorm'.d.`policyvar'!=0 & f`absnorm'.d.`policyvar'!=. & `esample', meanonly
	loc y1 = r(mean)
	loc depvar "`1'"	
	
	*  Calculate mean proxy before change in policy for 2nd axis in plot
	if "`proxy'"!="" {
		loc nproxy: word count `proxy'
		if `nproxy' ==1 {
			qui su `proxy' if f`absnorm'.d.`policyvar'!=0 & f`absnorm'.d.`policyvar'!=. & `esample', meanonly
			loc x1 = r(mean)
		}
		else loc x1 = .
	}
	
	
	* Variables for overlay plots
	
	* Need the ols estimates for y and x
	* Do not exclude vars other than m1
	*loc toexc = "_k_eq_m1"
	*unab included2: _k_eq_*
	*loc included2 : list included2 - toexc
	
	_estimates hold main
	
	qui _eventols `varlist' [`weight'`exp'] if `touse' , panelvar(`panelvar') timevar(`timevar') policyvar(`policyvar') lwindow(`lwindow') rwindow(`rwindow') `fe' `te' nogen nodrop kvars(_k) norm(`norm0')
	mat `deltaov' = r(delta)
	mat `Vdeltaov' = r(Vdelta)
	*mat `deltay' = `bby'[1,${names}]
	*mat `Vdeltay' = `VVy'[${names},${names}]
	qui _eventols `proxy' [`weight'`exp'] if `touse', panelvar(`panelvar') timevar(`timevar') policyvar(`policyvar') lwindow(`lwindow') rwindow(`rwindow') `fe' `te' nogen nodrop kvars(_k) norm(`norm0')
	mat `deltax' = r(delta)
	mat `Vdeltax' = r(Vdelta)		
	*mat `deltax' = `bb'[1,${names}]
	* mat `Vdeltax' = `VV'[${names},${names}]
	* Scaling factor
	loc ivnormcomma = strtrim("`ivnorm'")
	loc ivnorms : list sizeof ivnormcomma
	loc ivnormcomma : subinstr local ivnormcomma " " ",", all
	if `ivnorms'>1 loc scfactlead = -max(`ivnormcomma')
	else loc scfactlead = -`ivnormcomma'
	mat Mfn = `deltaov'[1,"_k_eq_m`scfactlead'"]	
	mat Mfd = `deltax'[1,"_k_eq_m`scfactlead'"]
	loc fn = Mfn[1,1]
	loc fd = Mfd[1,1]
	loc factor = `fn'/`fd'
	* Scale x estimates by factor
	mat `deltaxsc' = `factor'*`deltax'	
		
	* Drop variables
	if "`savek'" == "" {
		cap confirm var _k_eq_p0
		if !_rc drop _k_eq*	
		cap confirm var __k
		if !_rc qui drop __k
		if "`trend'"!="" qui drop _ttrend		
	}
	else {
		ren __k `savek'_evtime
		ren _k_eq* `savek'_eq*
		if "`trend'"!="" ren _ttrend `savek'_trend	
	}
	if "`instype'"=="numlist" | "`instype'"=="mixed" {
		foreach v in `leadivs' {
			drop `v'
		}
	}
	
	
	
	* Returns
	
	_estimates unhold main
	
	return matrix b = `bb'
	return matrix V = `VV'
	return matrix delta = `delta'
	return matrix Vdelta = `Vdelta'
	return matrix deltaov = `deltaov'
	return matrix Vdeltaov = `Vdeltaov'
	return matrix deltax = `deltax'
	return matrix Vdeltax = `Vdeltax'
	return matrix deltaxsc = `deltaxsc'
	loc names: subinstr local names ".." " ", all
	loc names: subinstr local names `"""' "", all
	return local names = `"`names'"'
	* "	
	return local cmd = "`cmd'"	
	return local df = `df'
	return local komit = "`komit'"
	return local kmiss = "`kmiss'"
	return local y1 = `y1'
	return local depvar = "`depvar'"
	if `x1'!=. return local x1 = `x1'
	return local method = "iv"
	
end
