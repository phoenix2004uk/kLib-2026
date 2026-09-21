{
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	local OrbitalSpeed is {
		parameter h is altitude, a is obt:semimajoraxis, b is body.
		return sqrt(b:mu * (2/(h + b:radius) - 1/a)).
	}.
	local OrbitalPeriod is {
		parameter a is obt:semimajoraxis, b is body.
		if a <= 0 { print "Error: OrbitalPeriod is only valid for elliptical orbits". }
		return 2 * constant:pi * sqrt(a^3 / b:mu).
	}.
	local TrueAnomalyEta is {
		parameter V1,
			P is obt:period,
			V0 is obt:trueanomaly,
			e is obt:eccentricity.
		if e < 1 {
			local dM is mod(360 + OrbitalParameters:M(OrbitalParameters:E(V1, e), e) - OrbitalParameters:M(OrbitalParameters:E(V0, e), e), 360).
			if dM < 1e-9 or 360 - dM < 1e-9 set dM to 0.
			return P * dM / 360.
		}
		print "Error: TrueAnomalyEta is only valid for elliptical orbits".
		return false.
	}.
	local TrueAnomalyEtaHyperbolic is {
		parameter V1, V0 is obt:trueanomaly,
			a is obt:semimajoraxis,
			e is obt:eccentricity,
			b is body.
		if e > 1 {
			local dM is OrbitalParameters:Mh(OrbitalParameters:F(V1, e), e) - OrbitalParameters:Mh(OrbitalParameters:F(V0, e), e).
			if abs(dM) < 1e-9 set dM to 0.
			return dM / (sqrt(b:mu / (-a)^3) * constant:radToDeg).
		}
		print "Error: TrueAnomalyEtaHyperbolic is only valid for hyperbolic orbits.".
		return false.
	}.
	export(lex(
		"v", OrbitalSpeed,
		"vh", {
			parameter h, h1, h2, b is body.
			return OrbitalSpeed(h, OrbitalParameters:a(h1, h2, b), b).
		},
		"Ve", {
			parameter b is body, h is altitude.
			return sqrt(2 * b:mu / (h + b:radius)).
		},
		"P", OrbitalPeriod,
		"Ph", {
			parameter h1, h2, b is body.
			return OrbitalPeriod(OrbitalParameters:a(h1, h2, b), b).
		},
		"h", {
			parameter targetOrbitable.
			return vcrs(targetOrbitable:position - targetOrbitable:body:position, targetOrbitable:velocity:orbit).
		},
		"hAt", {
			parameter targetOrbitable, ut.
			return vcrs(positionAt(targetOrbitable,ut) - targetOrbitable:body:position, velocityAt(targetOrbitable, ut):orbit).
		},
		"etaV", TrueAnomalyEta,
		"dtV", {
			parameter Vdelta,
				P is obt:period,
				V0 is obt:trueanomaly,
				e is obt:eccentricity.
			if e < 1 {
				local revolutions is choose ceiling(Vdelta / 360) if VDelta < 0 else floor(Vdelta / 360).
				local Vremainder is Vdelta - revolutions * 360.
				local dM is OrbitalParameters:M(OrbitalParameters:E(mod(360 + V0 + Vremainder, 360), e), e) - OrbitalParameters:M(OrbitalParameters:E(V0, e), e).
				if Vremainder > 0 and dM < 0 set dM to dM + 360.
				if Vremainder < 0 and dM > 0 set dM to dM - 360.
				return P * (revolutions + dM / 360).
			}
			print "Error: TrueAnomalyArcTime is only valid for elliptical orbits".
			return false.
		},
		"etaAN", {
			parameter w is obt:argumentOfPeriapsis,
				P is obt:period,
				V0 is obt:trueanomaly,
				e is obt:eccentricity.
			return TrueAnomalyEta(OrbitalParameters:Van(w, e), P, V0, e).
		},
		"etaDN", {
			parameter w is obt:argumentOfPeriapsis,
				P is obt:period,
				V0 is obt:trueanomaly,
				e is obt:eccentricity.
			return TrueAnomalyEta(OrbitalParameters:Vdn(w, e), P, V0, e).
		},
		"etaVh", TrueAnomalyEtaHyperbolic,
		"etaANh", {
			parameter w is obt:argumentOfPeriapsis,
				V0 is obt:trueanomaly,
				a is obt:semimajoraxis,
				e is obt:eccentricity,
				b is body.
			return TrueAnomalyEtaHyperbolic(OrbitalParameters:Van(w, e), V0, a, e, b).
		},
		"etaDNh", {
			parameter w is obt:argumentOfPeriapsis,
				V0 is obt:trueanomaly,
				a is obt:semimajoraxis,
				e is obt:eccentricity,
				b is body.
			return TrueAnomalyEtaHyperbolic(OrbitalParameters:Vdn(w, e), V0, a, e, b).
		}
	)).
}