{
	local math is import("util/math-v1").
	local FLOATING_POINT_TOLERANCE is 1e-9.

	// works for elliptical orbits (e<1 -> a>0) and hyperbolic trajectories (e>1 -> a<0)
	function SemiMajorAxis {
		parameter h1, h2, b is body.

		if h1 < 0 or h2 < 0 { print "Error: SemiMajorAxis is only valid for elliptical orbits". }

		return (h1 + h2) / 2 + b:radius.
	}

	// Returns the maximum absolute true anomaly.
	// Elliptical: returns 180 degrees.
	// Parabolic: returns 180 degrees (asymptotic limit).
	// Hyperbolic: returns the asymptotic true anomaly.
	// Physical open trajectory is -Vlimit < V < +Vlimit.
	// Note: kOS represents elliptical true anomaly as 0..360,
	//       but open-orbit true anomaly as -180..180.
	function TrueAnomalyLimit {
		parameter e is orbit:eccentricity.

		if (e < 1) return 180.
		return arccos(max(-1, -1/e)).
	}

	// works for elliptical orbits and hyperbolic trajectories
	function TrueAnomalyOfAN {
		parameter w is orbit:argumentOfPeriapsis, e is orbit:eccentricity.

		if e < 1 return mod(360 - w, 360).
		return -w.
		// if i < 0 return mod(180 - w, 360).
		// return mod(360 - w,360).
	}

	// works for elliptical orbits and hyperbolic trajectories
	function TrueAnomalyOfDN {
		parameter w is orbit:argumentOfPeriapsis, e is orbit:eccentricity.

		if e < 1 return mod(540 - w, 360).
		return 180 - w.
		// if i < 0 return mod(360 - w, 360).
		// return mod(540 - w,360).
	}

	// for elliptical orbits only, e<1
	function EccentricAnomaly {
		parameter V0, e is orbit:eccentricity.

		if e >= 1 { print "Error: EccentricAnomaly is only valid for elliptical orbits". }

		local VN is mod(V0 + 360, 360).

		local eccentricAnomalyDegrees is arccos( (e + cos(VN)) / (1 + e * cos(VN))).
		if (VN > 180) {
			set eccentricAnomalyDegrees to 360 - eccentricAnomalyDegrees.
		}
		return eccentricAnomalyDegrees.
	}

	// for hyperbolic trajectories only, e>1
	// Note: caller must ensure the Hyperbolic Anomaly (F) is within the domain limit from TrueAnomalyLimit(e)
	function HyperbolicAnomaly {
		parameter V0, e is orbit:eccentricity.

		if e <= 1 { print "Error: HyperbolicAnomaly is only valid for hyperbolic orbits". }

		local F is math:acosh((e + cos(V0)) / (1 + e * cos(V0))) * constant:radToDeg.

		if V0 < 0 {
			return -F.
		}

		return F.
	}

	// for elliptical orbits only, e<1
	function MeanAnomaly {
		parameter eccentricAnomalyDegrees, e is orbit:eccentricity.

		if e >= 1 { print "Error: MeanAnomaly is only valid for elliptical orbits". }

		return eccentricAnomalyDegrees - e * sin(eccentricAnomalyDegrees) * constant:radToDeg.
	}

	// for hyperbolic trajectories only, e>1
	// Note: caller must ensure the Hyperbolic Anomaly (F) is within the domain limit from TrueAnomalyLimit(e)
	function HyperbolicMeanAnomaly {
		parameter F, e is orbit:eccentricity.

		if e <= 1 { print "Error: HyperbolicMeanAnomaly is only valid for hyperbolic orbits". }

		local Fr is F * constant:degToRad.
		return (e * math:sinh(Fr) - Fr) * constant:radToDeg.
	}

	// works for elliptical orbits and para/hyperbolic trajectories by using semi-latus rectum: p=rp(1+e)
	function TrueAnomalyRadius {
		parameter V0,
			rp is orbit:periapsis + orbit:body:radius,
			e is orbit:eccentricity.

		local p is rp * (1 + e).
		return p / (1 + e * cos(V0)).
	}

	// works for elliptical orbits and para/hyperbolic trajectories
	// circular orbits return representative opposite anomalies 0 and 180
	function TrueAnomaliesAtRadius {
		parameter radius,
			rp is orbit:periapsis + orbit:body:radius,
			e is orbit:eccentricity.

		if e = 0 {
			// print "Error: TrueAnomaliesAtRadius is not valid for circular orbits".
			return list(0, 180).
		}

		local p is rp * (1 + e).
		local x is (p / radius - 1) / e.

		if abs(x) > 1 {
			if abs(x) - 1 < FLOATING_POINT_TOLERANCE {
				set x to round(x).
			} else {
				print "Error: TrueAnomaliesAtRadius cannot determine V from invalid orbital geometry".
				return list().
			}
		}

		local V0 is arccos(x).

		if V0 < FLOATING_POINT_TOLERANCE return list(0).
		if e < 1 {
			if 180 - V0 < FLOATING_POINT_TOLERANCE return list(180).
			return list(V0, 360 - V0).
		}
		return list(-V0, V0).
	}

	export(lex(
		"a", SemiMajorAxis@,
		"Vlim", TrueAnomalyLimit@,
		"Van", TrueAnomalyOfAN@,
		"Vdn", TrueAnomalyOfDN@,
		"Vr", TrueAnomalyRadius@,
		"Vh", { // TrueAnomalyAltitude
			parameter V0,
				rp is orbit:periapsis + orbit:body:radius,
				e is orbit:eccentricity,
				b is body.
			return TrueAnomalyRadius(V0, rp, e) - b:radius.
		},
		"rV", TrueAnomaliesAtRadius@,
		"hV", { // TrueAnomaliesAtAltitude
			parameter h,
				rp is orbit:periapsis + orbit:body:radius,
				e is orbit:eccentricity,
				b is body.

			return TrueAnomaliesAtRadius(h + b:radius, rp, e).
		},
		"E", EccentricAnomaly@,
		"F", HyperbolicAnomaly@,
		"M", MeanAnomaly@,
		"Mh", HyperbolicMeanAnomaly@
	)).
}