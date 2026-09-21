{
	local math is import("util/math-v1").
	local PI is constant:PI.
	local DegToRad is constant:DegToRad.
	local RadToDeg is constant:RadToDeg.
	local LambertFail is {
		parameter reason.
		return lex("valid",false,"reason",reason).
	}.
	local LambertXToTOF is {
		parameter x,lambda,revolutions.
		local distanceFromOne is abs(x-1).
		local lambda2 is lambda^2.
		if distanceFromOne<0.2 and distanceFromOne>0.01 {
			local a is 1/(1-x^2).
			if a>0 {
				local alpha is 2*arccos(max(-1,min(1,x)))*DegToRad.
				local beta is 2*arcsin(sqrt(max(0,min(1,lambda2/a))))*DegToRad.
				if lambda<0 set beta to -beta.
				return a*sqrt(a)*(
					(alpha-sin(alpha*RadToDeg))
					-(beta-sin(beta*RadToDeg))
					+2*PI*revolutions
				)/2.
			}
			local alpha is 2*math:acosh(x).
			local beta is 2*math:asinh(sqrt(-lambda2/a)).
			if lambda<0 set beta to -beta.
			return -a*sqrt(-a)*(
				(beta-math:sinh(beta))-(alpha-math:sinh(alpha))
			)/2.
		}
		local E is x^2-1.
		local rho is abs(E).
		local z is sqrt(max(0,1+lambda2*E)).
		if distanceFromOne<0.01 {
			local dt is z-lambda*x.
			local zF is 0.5*(1-lambda-x*dt).
			local sum is 1.
			local term is 1.
			from { local j is 0. }
			until abs(term)<=1e-11 or j>=1000
			step { set j to j+1. }
			do {
				set term to term*(3+j)*(1+j)/(2.5+j)*zF/(j+1).
				set sum to sum+term.
			}
			return 2*dt^3*sum/3+2*dt*lambda+revolutions*PI/rho^1.5.
		}
		local y is sqrt(rho).
		local g is x*z-lambda*E.
		local d is 0.
		if E<0 set d to revolutions*PI+arccos(max(-1,min(1,g)))*DegToRad.
		else set d to ln(y*(z-lambda*x)+g).
		return (x-lambda*z-d/y)/E.
	}.
	local LambertTOFDerivatives is {
		parameter x,T,lambda.
		local lambda2 is lambda^2.
		local lambda3 is lambda2*lambda.
		local oneMinusX2 is 1-x^2.
		local y is sqrt(1-lambda2*oneMinusX2).
		local y3 is y^3.
		local DT is (3*T*x-2+2*lambda3*x/y)/oneMinusX2.
		local DDT is (3*T+5*x*DT+2*(1-lambda2)*lambda3/y3)/oneMinusX2.
		return V(DT,DDT,(7*x*DDT+8*DT-6*(1-lambda2)*lambda2*lambda3*x/y3/y^2)/oneMinusX2).
	}.
	local LambertHouseholder is {
		parameter targetT,x0,lambda,revolutions,tolerance.
		local x is x0.
		from { local iteration is 0. }
		until iteration>=15
		step { set iteration to iteration+1. }
		do {
			local actualT is LambertXToTOF(x,lambda,revolutions).
			local derivatives is LambertTOFDerivatives(x,actualT,lambda).
			local delta is actualT-targetT.
			local DT is derivatives:x.
			local DDT is derivatives:y.
			local DT2 is DT^2.
			local denominator is DT*(DT2-delta*DDT)+derivatives:z*delta^2/6.
			if abs(denominator)<1e-15 return LambertFail("Lambert Householder denominator is singular").
			local xNew is x-delta*(DT2-delta*DDT/2)/denominator.
			if abs(x-xNew)<tolerance return lex("valid",true,"x",xNew,"iterations",iteration+1).
			set x to xNew.
		}
		return LambertFail("Lambert Householder iteration did not converge").
	}.
	local LambertSolveX is {
		parameter T,lambda,revolutions,branch.
		local lambda2 is lambda^2.
		local lambda3 is lambda2*lambda.
		local T00 is arccos(max(-1,min(1,lambda)))*DegToRad+lambda*sqrt(max(0,1-lambda2)).
		local NoLambertRevolutionExists is revolutions>0 and revolutions>floor(T/PI).
		if revolutions>0 and not NoLambertRevolutionExists {
			local TMin is T00+revolutions*PI.
			if T<TMin {
				local x is 0.
				from { local iteration is 0. }
				until iteration>=13
				step { set iteration to iteration+1. }
				do {
					local derivatives is LambertTOFDerivatives(x,TMin,lambda).
					local DT is derivatives:x.
					local DDT is derivatives:y.
					local denominator is DDT^2-DT*derivatives:z/2.
					if abs(denominator)<1e-15 break.
					local xNew is x-DT*DDT/denominator.
					if abs(x-xNew)<1e-13 break.
					set x to xNew.
					set TMin to LambertXToTOF(x,lambda,revolutions).
				}
				set NoLambertRevolutionExists to T<TMin.
			}
		}
		if NoLambertRevolutionExists return LambertFail("Requested Lambert revolution count has no solution").
		if revolutions=0 {
			local T1 is 2/3*(1-lambda3).
			local x0 is 0.
			if T>=T00 set x0 to -(T-T00)/(T-T00+4).
			else if T<=T1 set x0 to T1*(T1-T)/((2/5)*(1-lambda2*lambda3)*T)+1.
			else set x0 to (T/T00)^(ln(2)/ln(T1/T00))-1.
			return LambertHouseholder(T,x0,lambda,0,1e-5).
		}
		local tmp is 0.
		if branch="left" set tmp to ((revolutions*PI+PI)/(8*T))^(2/3).
		else if branch="right" set tmp to (8*T/(revolutions*PI))^(2/3).
		else return LambertFail("Lambert multi-revolution branch must be left or right").
		return LambertHouseholder(T,(tmp-1)/(tmp+1),lambda,revolutions,1e-8).
	}.
	export({
		parameter r1,r2,tof,mu,direction is "short",revolutions is 0,branch is "left",planeNormal is false.
		if tof<=0 return LambertFail("Lambert time of flight must be positive").
		if mu<=0 return LambertFail("Lambert gravitational parameter must be positive").
		if direction<>"short" and direction<>"long" return LambertFail("Lambert direction must be short or long").
		if revolutions<0 return LambertFail("Lambert revolution count cannot be negative").
		local r1mag is r1:mag.
		local r2mag is r2:mag.
		if r1mag<=0 or r2mag<=0 return LambertFail("Lambert position vectors must be non-zero").
		local chord is (r2-r1):mag.
		if chord<=1e-9 return LambertFail("Coincident Lambert endpoints are not supported").
		local semiperimeter is (chord+r1mag+r2mag)/2.
		local ir1 is r1/r1mag.
		local ir2 is r2/r2mag.
		local lambda2 is max(0,min(1,1-chord/semiperimeter)).
		local lambda is sqrt(lambda2).
		local endpointCross is -vcrs(ir1,ir2).
		local ih is false.
		if endpointCross:mag>1e-10 set ih to endpointCross:normalized.
		else {
			if not planeNormal:istype("Vector") return LambertFail("Lambert transfer plane is undefined; provide planeNormal").
			if planeNormal:mag<=1e-10 return LambertFail("Lambert planeNormal must be non-zero").
			set ih to planeNormal:normalized.
		}
		local it1 is (-vcrs(ih,ir1)):normalized.
		local it2 is (-vcrs(ih,ir2)):normalized.
		if direction="long" {
			set lambda to -lambda.
			set it1 to -it1.
			set it2 to -it2.
		}
		local T is sqrt(2*mu/semiperimeter^3)*tof.
		local xResult is LambertSolveX(T,lambda,revolutions,branch).
		if not xResult:valid return xResult.
		local x is xResult:x.
		local y is sqrt(max(0,1-lambda2+lambda2*x^2)).
		local gamma is sqrt(mu*semiperimeter/2).
		local rho is (r1mag-r2mag)/chord.
		local sigma is sqrt(max(0,1-rho^2)).
		local lambdaYMinusX is lambda*y-x.
		local lambdaYPlusX is lambda*y+x.
		local radial1 is gamma*(lambdaYMinusX-rho*lambdaYPlusX)/r1mag.
		local radial2 is -gamma*(lambdaYMinusX+rho*lambdaYPlusX)/r2mag.
		local tangential is gamma*sigma*(y+lambda*x).
		local departureVelocity is radial1*ir1+tangential/r1mag*it1.
		local arrivalVelocity is radial2*ir2+tangential/r2mag*it2.
		return lex(
			"valid",true,
			"departureVelocity",departureVelocity,
			"arrivalVelocity",arrivalVelocity,
			"direction",direction,
			"revolutions",revolutions,
			"branch",branch,
			"x",x,
			"y",y,
			"lambda",lambda,
			"T",T,
			"chord",chord,
			"semiperimeter",semiperimeter,
			"iterations",xResult:iterations
		).
	}).
}