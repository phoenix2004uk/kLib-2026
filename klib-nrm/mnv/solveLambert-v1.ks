{
	local math is import("math-v1").

	local MAXIMUM_LAMBERT_HOUSEHOLDER_ITERATIONS is 15,
		MAXIMUM_LAMBERT_HALLEY_ITERATIONS is 13,
		MAXIMUM_LAMBERT_HYPERGEOMETRIC_ITERATIONS is 1000,
		LAMBERT_ZERO_REV_X_TOLERANCE is 1e-5,
		LAMBERT_MULTI_REV_X_TOLERANCE is 1e-8,
		LAMBERT_HALLEY_X_TOLERANCE is 1e-13,
		LAMBERT_HYPERGEOMETRIC_TOLERANCE is 1e-11,
		LAMBERT_GEOMETRY_TOLERANCE is 1e-10,
		LAMBERT_DENOMINATOR_TOLERANCE is 1e-15,
		LAMBERT_ENDPOINT_TOLERANCE is 1e-9,
		BATTIN_LIMIT is 0.01,
		LAGRANGE_LIMIT is 0.2.

	function LambertFail {
		parameter reason.
		return lex("valid",false,"reason",reason).
	}

	function LambertHypergeometricF {
		parameter z.
		local sum is 1,
			term is 1.

		from { local j is 0. }
		until abs(term)<=LAMBERT_HYPERGEOMETRIC_TOLERANCE
			or j>=MAXIMUM_LAMBERT_HYPERGEOMETRIC_ITERATIONS
		step { set j to j+1. }
		do {
			set term to term*(3+j)*(1+j)/(2.5+j)*z/(j+1).
			set sum to sum+term.
		}
		return sum.
	}

	function LambertXToTOF {
		parameter x,lambda,revolutions.
		local distanceFromOne is abs(x-1),
			lambda2 is lambda^2.

		if distanceFromOne<LAGRANGE_LIMIT and distanceFromOne>BATTIN_LIMIT {
			local a is 1/(1-x^2).
			if a>0 {
				local alpha is 2*arccos(max(-1,min(1,x)))*constant:DegToRad,
					beta is 2*arcsin(sqrt(max(0,min(1,lambda2/a))))*constant:DegToRad.
				if lambda<0 set beta to -beta.
				return a*sqrt(a)*(
					(alpha-sin(alpha*constant:RadToDeg))
					-(beta-sin(beta*constant:RadToDeg))
					+2*constant:PI*revolutions
				)/2.
			}

			local alpha is 2*math:acosh(x),
				beta is 2*math:asinh(sqrt(-lambda2/a)).
			if lambda<0 set beta to -beta.
			return -a*sqrt(-a)*(
				(beta-math:sinh(beta))-(alpha-math:sinh(alpha))
			)/2.
		}

		local E is x^2-1,
			rho is abs(E),
			z is sqrt(max(0,1+lambda2*E)).

		if distanceFromOne<BATTIN_LIMIT {
			local dt is z-lambda*x,
				S1 is 0.5*(1-lambda-x*dt),
				Qh is 4/3*LambertHypergeometricF(S1).
			return (dt^3*Qh+4*lambda*dt)/2
				+revolutions*constant:PI/rho^1.5.
		}

		local y is sqrt(rho),
			g is x*z-lambda*E,
			d is 0.
		if E<0 {
			set d to revolutions*constant:PI
				+arccos(max(-1,min(1,g)))*constant:DegToRad.
		}
		else {
			local f is y*(z-lambda*x).
			set d to ln(f+g).
		}
		return (x-lambda*z-d/y)/E.
	}

	function LambertTOFDerivatives {
		parameter x,T,lambda.
		local lambda2 is lambda^2,
			lambda3 is lambda2*lambda,
			oneMinusX2 is 1-x^2,
			y is sqrt(1-lambda2*oneMinusX2),
			y2 is y^2,
			y3 is y^3,
			DT is (3*T*x-2+2*lambda3*x/y)/oneMinusX2,
			DDT is (3*T+5*x*DT+2*(1-lambda2)*lambda3/y3)/oneMinusX2,
			DDDT is (7*x*DDT+8*DT-6*(1-lambda2)*lambda2*lambda3*x/y3/y2)/oneMinusX2.
		return V(DT,DDT,DDDT).
	}

	function LambertHouseholder {
		parameter targetT,x0,lambda,revolutions,tolerance.
		local x is x0.

		from { local iteration is 0. }
		until iteration>=MAXIMUM_LAMBERT_HOUSEHOLDER_ITERATIONS
		step { set iteration to iteration+1. }
		do {
			local actualT is LambertXToTOF(x,lambda,revolutions),
				derivatives is LambertTOFDerivatives(x,actualT,lambda),
				delta is actualT-targetT,
				DT is derivatives:x,
				DDT is derivatives:y,
				DT2 is DT^2,
				denominator is DT*(DT2-delta*DDT)+derivatives:z*delta^2/6.
			if abs(denominator)<LAMBERT_DENOMINATOR_TOLERANCE
				return LambertFail("Lambert Householder denominator is singular").

			local xNew is x-delta*(DT2-delta*DDT/2)/denominator.
			if abs(x-xNew)<tolerance
				return lex("valid",true,"x",xNew,"iterations",iteration+1).
			set x to xNew.
		}
		return LambertFail("Lambert Householder iteration did not converge").
	}

	function LambertRevolutionExists {
		parameter targetT,lambda,revolutions,T00.
		if revolutions<=0 return true.
		if revolutions>floor(targetT/constant:PI) return false.

		local TMin is T00+revolutions*constant:PI.
		if targetT>=TMin return true.

		local x is 0.
		from { local iteration is 0. }
		until iteration>=MAXIMUM_LAMBERT_HALLEY_ITERATIONS
		step { set iteration to iteration+1. }
		do {
			local derivatives is LambertTOFDerivatives(x,TMin,lambda),
				DT is derivatives:x,
				DDT is derivatives:y,
				denominator is DDT^2-DT*derivatives:z/2.
			if abs(denominator)<LAMBERT_DENOMINATOR_TOLERANCE break.

			local xNew is x-DT*DDT/denominator.
			if abs(x-xNew)<LAMBERT_HALLEY_X_TOLERANCE break.
			set x to xNew.
			set TMin to LambertXToTOF(x,lambda,revolutions).
		}
		return targetT>=TMin.
	}

	function LambertSolveX {
		parameter T,lambda,revolutions,branch is "left".
		local lambda2 is lambda^2,
			lambda3 is lambda2*lambda,
			T00 is arccos(max(-1,min(1,lambda)))*constant:DegToRad+lambda*sqrt(max(0,1-lambda2)).

		if not LambertRevolutionExists(T,lambda,revolutions,T00)
			return LambertFail("Requested Lambert revolution count has no solution").

		if revolutions=0 {
			local T1 is 2/3*(1-lambda3),
				x0 is 0.
			if T>=T00
				set x0 to -(T-T00)/(T-T00+4).
			else if T<=T1
				set x0 to T1*(T1-T)/((2/5)*(1-lambda2*lambda3)*T)+1.
			else
				set x0 to (T/T00)^(ln(2)/ln(T1/T00))-1.
			return LambertHouseholder(T,x0,lambda,0,LAMBERT_ZERO_REV_X_TOLERANCE).
		}

		if branch<>"left" and branch<>"right"
			return LambertFail("Lambert multi-revolution branch must be left or right").

		local tmp is 0.
		if branch="left"
			set tmp to ((revolutions*constant:PI+constant:PI)/(8*T))^(2/3).
		else
			set tmp to (8*T/(revolutions*constant:PI))^(2/3).
		return LambertHouseholder(
			T,(tmp-1)/(tmp+1),lambda,revolutions,LAMBERT_MULTI_REV_X_TOLERANCE
		).
	}

	function solveLambert {
		parameter r1,r2,tof,mu,
			direction is "short",revolutions is 0,branch is "left",planeNormal is false.

		if tof<=0 return LambertFail("Lambert time of flight must be positive").
		if mu<=0 return LambertFail("Lambert gravitational parameter must be positive").
		if direction<>"short" and direction<>"long"
			return LambertFail("Lambert direction must be short or long").
		if revolutions<0 return LambertFail("Lambert revolution count cannot be negative").

		local r1mag is r1:mag,
			r2mag is r2:mag.
		if r1mag<=0 or r2mag<=0
			return LambertFail("Lambert position vectors must be non-zero").

		local chord is (r2-r1):mag.
		if chord<=LAMBERT_ENDPOINT_TOLERANCE
			return LambertFail("Coincident Lambert endpoints are not supported").

		local semiperimeter is (chord+r1mag+r2mag)/2,
			ir1 is r1/r1mag,
			ir2 is r2/r2mag,
			lambda2 is max(0,min(1,1-chord/semiperimeter)),
			lambda is sqrt(lambda2),
			endpointCross is -vcrs(ir1,ir2),
			ih is false.

		if endpointCross:mag>LAMBERT_GEOMETRY_TOLERANCE
			set ih to endpointCross:normalized.
		else {
			if not planeNormal:istype("Vector")
				return LambertFail("Lambert transfer plane is undefined; provide planeNormal").
			if planeNormal:mag<=LAMBERT_GEOMETRY_TOLERANCE
				return LambertFail("Lambert planeNormal must be non-zero").
			set ih to planeNormal:normalized.
		}

		local it1 is (-vcrs(ih,ir1)):normalized,
			it2 is (-vcrs(ih,ir2)):normalized.
		if direction="long" {
			set lambda to -lambda.
			set it1 to -it1.
			set it2 to -it2.
		}

		local T is sqrt(2*mu/semiperimeter^3)*tof,
			xResult is LambertSolveX(T,lambda,revolutions,branch).
		if not xResult:valid return xResult.

		local x is xResult:x,
			y is sqrt(max(0,1-lambda2+lambda2*x^2)),
			gamma is sqrt(mu*semiperimeter/2),
			rho is (r1mag-r2mag)/chord,
			sigma is sqrt(max(0,1-rho^2)),
			lambdaYMinusX is lambda*y-x,
			lambdaYPlusX is lambda*y+x,
			radial1 is gamma*(lambdaYMinusX-rho*lambdaYPlusX)/r1mag,
			radial2 is -gamma*(lambdaYMinusX+rho*lambdaYPlusX)/r2mag,
			tangential is gamma*sigma*(y+lambda*x),
			departureVelocity is radial1*ir1+tangential/r1mag*it1,
			arrivalVelocity is radial2*ir2+tangential/r2mag*it2.

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
	}

	export(solveLambert@).
}
