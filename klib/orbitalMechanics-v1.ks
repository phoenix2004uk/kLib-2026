// #include "kldr-stub.ks"
{
	local OrbitalParameters is import("OrbitalParameters-v1").

	// VisViva equation
	function OrbitalSpeed {
		parameter h is altitude, a is orbit:semimajoraxis, b is body.

		local hr is h + b:radius.
		return sqrt(b:mu * (2/hr - 1/a)).
	}

	function EscapeVelocity {
		parameter b is body, h is altitude.

		return sqrt(2 * b:mu / (h + b:radius)).
	}

	function OrbitalPeriod {
		parameter a is orbit:semimajoraxis, b is body.

		if a <= 0 { print "Error: OrbitalPeriod is only valid for elliptical orbits". }

		return 2 * constant:pi * sqrt(a^3 / b:mu).
	}

	function TrueAnomalyEta {
		parameter V1, P is orbit:period, V0 is orbit:trueanomaly, e is orbit:eccentricity.

		if e >= 1 { print "Error: TrueAnomalyEta is only valid for elliptical orbits". }

		local n is 360 / P.

		local E0 is OrbitalParameters:E(V0, e).
		local M0 is OrbitalParameters:M(E0, e).

		local E1 is OrbitalParameters:E(V1, e).
		local M1 is OrbitalParameters:M(E1, e).

		local t is (M1 - M0) / n.
		if t < 0 set t to t + P.
		return t.
	}

	function TrueAnomalyEtaAN {
		parameter w is orbit:argumentOfPeriapsis,
			P is orbit:period,
			V0 is orbit:trueanomaly,
			e is orbit:eccentricity.
		
		return TrueAnomalyEta(OrbitalParameters:Van(w, e), P, V0, e).
	}

	function TrueAnomalyEtaDN {
		parameter w is orbit:argumentOfPeriapsis,
			P is orbit:period,
			V0 is orbit:trueanomaly,
			e is orbit:eccentricity.
		
		return TrueAnomalyEta(OrbitalParameters:Vdn(w, e), P, V0, e).
	}

	// Note: caller must ensure the Hyperbolic Anomaly (V1) is within the domain limit from TrueAnomalyLimit(e)
	function TrueAnomalyEtaHyperbolic {
		parameter V1, V0 is orbit:trueanomaly,
			a is orbit:semimajoraxis,
			e is orbit:eccentricity,
			b is body.

		if e <= 1 {
			print "Error: TrueAnomalyEtaHyperbolic is only valid for hyperbolic orbits.".
		}

		local F0 is OrbitalParameters:F(V0, e).
		local M0 is OrbitalParameters:Mh(F0, e).

		local F1 is OrbitalParameters:F(V1, e).
		local M1 is OrbitalParameters:Mh(F1, e).

		// Hyperbolic mean motion, converted from rad/s to deg/s.
		local n is sqrt(b:mu / (-a)^3) * constant:radToDeg.

		return (M1 - M0) / n.
	}

	function TrueAnomalyEtaHyperbolicAN {
		parameter w is orbit:argumentOfPeriapsis,
			V0 is orbit:trueanomaly,
			a is orbit:semimajoraxis,
			e is orbit:eccentricity,
			b is body.
		
		return TrueAnomalyEtaHyperbolic(OrbitalParameters:Van(w, e), V0, a, e, b).
	}

	function TrueAnomalyEtaHyperbolicDN {
		parameter w is orbit:argumentOfPeriapsis,
			V0 is orbit:trueanomaly,
			a is orbit:semimajoraxis,
			e is orbit:eccentricity,
			b is body.

		return TrueAnomalyEtaHyperbolic(OrbitalParameters:Vdn(w, e), V0, a, e, b).
	}

	export(lex(
		"v", OrbitalSpeed@,
		"vh", { parameter h, h1, h2, b is body. return OrbitalSpeed(h, OrbitalParameters:a(h1, h2, b), b). },
		"Ve", EscapeVelocity@,
		"P", OrbitalPeriod@,
		"Ph", { parameter h1, h2, b is body. return OrbitalPeriod(OrbitalParameters:a(h1, h2, b), b). },
		"etaV", TrueAnomalyEta@,
		"etaAN", TrueAnomalyEtaAN@,
		"etaDN", TrueAnomalyEtaDN@,
		"etaVh", TrueAnomalyEtaHyperbolic@,
		"etaANh", TrueAnomalyEtaHyperbolicAN@,
		"etaDNh", TrueAnomalyEtaHyperbolicDN@
	)).
}