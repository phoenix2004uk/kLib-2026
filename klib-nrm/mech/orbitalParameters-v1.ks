{
	local math is import("util/math-v1").
	local RadToDeg is constant:RadToDeg.
	local TrueAnomalyRadius is {
		parameter V0, a is obt:semimajoraxis, e is obt:eccentricity.
		return (a * (1 - e^2)) / (1 + e * cos(V0)).
	}.
	export(lex(
		"a", {
			parameter h1, h2, b is body.
			if h1 < 0 or h2 < 0 { print "Error: SemiMajorAxis is only valid for elliptical orbits". }
			return (h1 + h2) / 2 + b:radius.
		},
		"Vlim", {
			parameter e is obt:eccentricity.
			if (e < 1) return 180.
			return arccos(max(-1, -1/e)).
		},
		"Van", {
			parameter w is obt:argumentOfPeriapsis, e is obt:eccentricity.
			if e < 1 return mod(360 - w, 360).
			return -w.
		},
		"Vdn", {
			parameter w is obt:argumentOfPeriapsis, e is obt:eccentricity.
			if e < 1 return mod(540 - w, 360).
			return 180 - w.
		},
		"Vr", TrueAnomalyRadius,
		"Vh", {
			parameter V0, a is obt:semimajoraxis, e is obt:eccentricity, b is body.
			return TrueAnomalyRadius(V0, a, e) - b:radius.
		},
		"E", {
			parameter V0, e is obt:eccentricity.
			if e >= 1 { print "Error: EccentricAnomaly is only valid for elliptical orbits". }
			local VN is mod(V0 + 360, 360).
			local eccentricAnomalyDegrees is arccos( (e + cos(VN)) / (1 + e * cos(VN))).
			if (VN > 180) {
				set eccentricAnomalyDegrees to 360 - eccentricAnomalyDegrees.
			}
			return eccentricAnomalyDegrees.
		},
		"F", {
			parameter V0, e is obt:eccentricity.
			if e <= 1 { print "Error: HyperbolicAnomaly is only valid for hyperbolic orbits". }
			local F is math:acosh((e + cos(V0)) / (1 + e * cos(V0))) * RadToDeg.
			if V0 < 0 {
				return -F.
			}
			return F.
		},
		"M", {
			parameter eccentricAnomalyDegrees, e is obt:eccentricity.
			if e >= 1 { print "Error: MeanAnomaly is only valid for elliptical orbits". }
			return eccentricAnomalyDegrees - e * sin(eccentricAnomalyDegrees) * RadToDeg.
		},
		"Mh", {
			parameter F, e is obt:eccentricity.
			if e <= 1 { print "Error: HyperbolicMeanAnomaly is only valid for hyperbolic orbits". }
			local Fr is F * constant:degToRad.
			return (e * math:sinh(Fr) - Fr) * RadToDeg.
		}
	)).
}