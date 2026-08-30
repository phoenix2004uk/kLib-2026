// #include "../lib-v1/kldr-stub.ks"
local OrbitalParameters is import("orbitalParameters-v1").
local orbitalMechanics is import("orbitalMechanics-v1").
clearScreen.

// ------------------------------------------------------------
// Orbital Mechanics Test Suite
//
// Requires:
//   OrbitalParameters
//   OrbitalMechanics
//
// Tests:
//   1. Circular / near-circular ellipse
//   2. Prograde eccentric ellipse
//   3. Retrograde eccentric ellipse
//   4. Prograde hyperbola
//   5. Retrograde hyperbola
//   6. Hyperbola with node at periapsis
//
// The script waits for each requested orbit before running its
// associated tests. Spawn/set the vessel into the requested
// orbit, then let the script continue.
// ------------------------------------------------------------

local ResumeTest is 1.

// ------------------------------------------------------------
// Test helpers
// ------------------------------------------------------------

local function TimeFormat {
	parameter seconds.

	local secs is abs(seconds).

	local days is floor(secs / 21_600).
	set secs to secs - days * 21_600.

	local hrs is floor(secs / 3_600).
	set secs to secs - hrs * 3_600.

	local mins is floor(secs / 60).
	set secs to secs - mins * 60.

	local strTime is days + "d, " +
		hrs + "h " +
		mins + "m" +
		round(secs, 3) + "s".
	
	if seconds < 0 return "-" + strTime.
	return strTime.
}

local function PrintOrbit {
	print "--- Current Orbit ---".
	print "Body: " + ship:body:name.
	print "a:    " + orbit:semimajoraxis.
	print "e:    " + orbit:eccentricity.
	print "i:    " + orbit:inclination.
	print "LAN:  " + orbit:lan.
	print "w:    " + orbit:argumentofperiapsis.
	print "V:    " + orbit:trueanomaly.
	print "Pe:   " + orbit:periapsis.
	print "Ap:   " + orbit:apoapsis.
	print "P:    " + (choose orbit:period if orbit:eccentricity < 1 else "Infinity").
	print "--------------------".
}

local function WaitForOrbit {
	parameter eMin, eMax, iMin, iMax.

	print "".
	print "Waiting for orbit:".
	print "  e = " + eMin + " .. " + eMax.
	print "  i = " + iMin + " .. " + iMax.
	print "".

	wait until (
		orbit:eccentricity >= eMin
		and orbit:eccentricity <= eMax
		and orbit:inclination >= iMin
		and orbit:inclination <= iMax
	).

	print "Orbit detected.".
	PrintOrbit().
	wait 1.
}


// ------------------------------------------------------------
// Convert a 0..360 angle to -180..180.
//
// This is ONLY used to display the equivalent open-orbit
// representation. It does not alter the library functions.
// ------------------------------------------------------------

local function OpenOrbitAngle {
	parameter theta.

	local result is mod(theta + 180, 360) - 180.

	return result.
}


// ------------------------------------------------------------
// Print AN / DN geometry.
//
// This is intentionally diagnostic rather than an assertion.
// It lets us compare:
//
//   LAN
//   inclination
//   argument of periapsis
//   current true anomaly
//   current Van/Vdn result
//   Van/Vdn converted to the open-orbit range
//
// This is particularly important for retrograde and
// hyperbolic trajectories.
// ------------------------------------------------------------

local function PrintNodeGeometry {
	parameter hyperbolic.

	local i is orbit:inclination.
	local ecc is orbit:eccentricity.
	local lan is orbit:lan.
	local w is orbit:argumentofperiapsis.
	local Vc is orbit:trueanomaly.

	local Vlim is OrbitalParameters:Vlim(ecc).
	local Van is OrbitalParameters:Van(w, ecc).
	local Vdn is OrbitalParameters:Vdn(w, ecc).

	print "--- Node Geometry ---".
	print "LAN:       " + lan.
	print "i:         " + i.
	print "w:         " + w.
	print "V current: " + Vc.
	print "Vlim:      ±" + Vlim.
	print "Van raw:   " + Van.
	print "Vdn raw:   " + Vdn.

	print "Van open:  " + OpenOrbitAngle(Van).
	print "Vdn open:  " + OpenOrbitAngle(Vdn).

	if hyperbolic {
		local Vinf is arccos(-1 / ecc).

		print "V infinity: +/-" + Vinf.
		print "--------------------".
		print "Hyperbolic physical range:".
		print "  -" + Vinf + " < V < +" + Vinf.
	}.

	print "--------------------".
}


// ------------------------------------------------------------
// Elliptical anomaly test
// ------------------------------------------------------------

local function TestEllipticalAnomalies {
	print "".
	print "========================================".
	print "TEST: Elliptical E / M / ETA".
	print "========================================".

	local Vc is orbit:trueanomaly.
	local ecc is orbit:eccentricity.
	local P is orbit:period.

	print "V  = " + Vc.
	print "e  = " + ecc.
	print "P  = " + P.

	local E is OrbitalParameters:E(Vc, ecc).
	local M is OrbitalParameters:M(E, ecc).

	print "E  = " + E.
	print "M  = " + M.

	print "ETA to periapsis (V=0): ".
	print TimeFormat(OrbitalMechanics:etaV(0, P, Vc, ecc)).

	print "ETA to V=90: ".
	print TimeFormat(OrbitalMechanics:etaV(90, P, Vc, ecc)).

	print "ETA to V=180: ".
	print TimeFormat(OrbitalMechanics:etaV(180, P, Vc, ecc)).

	print "ETA to V=270: ".
	print TimeFormat(OrbitalMechanics:etaV(270, P, Vc, ecc)).
}


// ------------------------------------------------------------
// Elliptical AN / DN test
// ------------------------------------------------------------

local function TestEllipticalNodes {
	print "".
	print "========================================".
	print "TEST: Elliptical AN / DN".
	print "========================================".

	local w is orbit:argumentofperiapsis.
	local Vc is orbit:trueanomaly.
	local P is orbit:period.
	local ecc is orbit:eccentricity.

	local Vlim is OrbitalParameters:Vlim(ecc).
	local Van is OrbitalParameters:Van(w, ecc).
	local Vdn is OrbitalParameters:Vdn(w, ecc).

	print "w    = " + w.
	print "V    = " + Vc.
	print "Vlim = ±" + Vlim.
	print "Van  = " + Van.
	print "Vdn  = " + Vdn.

	print "ETA to AN: ".
	print TimeFormat(OrbitalMechanics:etaAN(w, P, Vc, ecc)).

	print "ETA to DN: ".
	print TimeFormat(OrbitalMechanics:etaDN(w, P, Vc, ecc)).

	PrintNodeGeometry(false).

	print "========================================".
}


// ------------------------------------------------------------
// Elliptical radius / velocity test
// ------------------------------------------------------------

local function TestEllipticalDynamics {
	print "".
	print "========================================".
	print "TEST: Elliptical radius / velocity".
	print "========================================".

	local Vc is orbit:trueanomaly.
	local a is orbit:semimajoraxis.
	local ecc is orbit:eccentricity.
	local b is ship:body.

	local Vr is OrbitalParameters:Vr(Vc, a, ecc).
	local h is Vr - b:radius.

	local currentR is b:radius + ship:altitude.

	print "V        = " + Vc.
	print "KSP r    = " + currentR.
	print "Calc r   = " + Vr.
	print "KSP alt  = " + ship:altitude.
	print "Calc alt = " + h.

	print "KSP speed  = " + ship:velocity:orbit:mag.
	print "Calc speed = " + OrbitalMechanics:v(h, a, b).

	print "========================================".
}


// ------------------------------------------------------------
// Hyperbolic anomaly test
// ------------------------------------------------------------

local function TestHyperbolicAnomalies {
	print "".
	print "========================================".
	print "TEST: Hyperbolic F / Mh / ETA".
	print "========================================".

	local Vc is orbit:trueanomaly.
	local ecc is orbit:eccentricity.
	local a is orbit:semimajoraxis.
	local b is ship:body.

	print "V = " + Vc.
	print "e = " + ecc.
	print "a = " + a.

	local F is OrbitalParameters:F(Vc, ecc).
	local Mh is OrbitalParameters:Mh(F, ecc).

	print "F  = " + F.
	print "Mh = " + Mh.

	print "ETA to periapsis (V=0): ".
	print TimeFormat(OrbitalMechanics:etaVh(0, Vc, a, ecc, b)).

	print "ETA from periapsis to current V: ".
	print TimeFormat(OrbitalMechanics:etaVh(Vc, 0, a, ecc, b)).

	print "========================================".
}


// ------------------------------------------------------------
// Hyperbolic AN / DN test
// ------------------------------------------------------------

local function TestHyperbolicNodes {
	print "".
	print "========================================".
	print "TEST: Hyperbolic AN / DN".
	print "========================================".

	local w is orbit:argumentofperiapsis.
	local Vc is orbit:trueanomaly.
	local a is orbit:semimajoraxis.
	local ecc is orbit:eccentricity.
	local b is ship:body.

	local Vlim is OrbitalParameters:Vlim(ecc).
	local Van is OrbitalParameters:Van(w, ecc).
	local Vdn is OrbitalParameters:Vdn(w, ecc).

	print "w    = " + w.
	print "V    = " + Vc.
	print "Vlim = ±" + Vlim.
	print "Van  = " + Van.
	print "Vdn  = " + Vdn.

	print "ETA to AN: ".
	if (abs(Van) < OrbitalParameters:Vlim(ecc)) {
		print TimeFormat(OrbitalMechanics:etaANh(w, Vc, a, ecc, b)).
	}
	else {
		print "Infinity".
	}

	print "ETA to DN: ".
	if (abs(Vdn) < OrbitalParameters:Vlim(ecc)) {
		print TimeFormat(OrbitalMechanics:etaDNh(w, Vc, a, ecc, b)).
	}
	else {
		print "Infinity".
	}

	PrintNodeGeometry(true).

	print "========================================".
}


// ------------------------------------------------------------
// Hyperbolic radius / velocity test
// ------------------------------------------------------------

local function TestHyperbolicDynamics {
	print "".
	print "========================================".
	print "TEST: Hyperbolic radius / velocity".
	print "========================================".

	local Vc is orbit:trueanomaly.
	local a is orbit:semimajoraxis.
	local ecc is orbit:eccentricity.
	local b is ship:body.

	local Vr is OrbitalParameters:Vr(Vc, a, ecc).
	local h is Vr - b:radius.

	local currentR is b:radius + ship:altitude.

	print "V        = " + Vc.
	print "KSP r    = " + currentR.
	print "Calc r   = " + Vr.
	print "KSP alt  = " + ship:altitude.
	print "Calc alt = " + h.

	print "KSP speed  = " + ship:velocity:orbit:mag.
	print "Calc speed = " + OrbitalMechanics:v(h, a, b).

	print "========================================".
}

clearScreen.
print "".
print "########################################".
print "# ORBITAL MECHANICS TEST SUITE".
print "########################################".

// ------------------------------------------------------------
// TEST 1 — Circular / near-circular ellipse
// ------------------------------------------------------------

if ResumeTest <= 1 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 1: Circular / near-circular ellipse".
	print "Required:".
	print "  e = 0 .. 0.02".
	print "  i = 0 .. 5 degrees".
	print "".

	WaitForOrbit(0, 0.02, 0, 5).

	TestEllipticalDynamics().
	TestEllipticalAnomalies().
}

// ------------------------------------------------------------
// TEST 2 — Prograde elliptical
// ------------------------------------------------------------

if ResumeTest <= 2 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 2: Prograde elliptical".
	print "Required:".
	print "  e = 0.45 .. 0.55".
	print "  i = 40 .. 50 degrees".
	print "".

	WaitForOrbit(0.45, 0.55, 40, 50).

	TestEllipticalDynamics().
	TestEllipticalAnomalies().
	TestEllipticalNodes().
}

// ------------------------------------------------------------
// TEST 3 — Retrograde elliptical
// ------------------------------------------------------------

if ResumeTest <= 3 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 3: Retrograde elliptical".
	print "Required:".
	print "  e = 0.45 .. 0.55".
	print "  i = 130 .. 140 degrees".
	print "".

	WaitForOrbit(0.45, 0.55, 130, 140).

	TestEllipticalDynamics().
	TestEllipticalAnomalies().
	TestEllipticalNodes().
}

// ------------------------------------------------------------
// TEST 4 — Prograde hyperbola
// ------------------------------------------------------------

if ResumeTest <= 4 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 4: Prograde hyperbolic".
	print "Required:".
	print "  e = 1.8 .. 2.2".
	print "  i = 40 .. 50 degrees".
	print "".

	WaitForOrbit(1.8, 2.2, 40, 50).

	TestHyperbolicDynamics().
	TestHyperbolicAnomalies().
	TestHyperbolicNodes().
}

// ------------------------------------------------------------
// TEST 5 — Retrograde hyperbola
// ------------------------------------------------------------

if ResumeTest <= 5 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 5: Retrograde hyperbolic".
	print "Required:".
	print "  e = 1.8 .. 2.2".
	print "  i = 130 .. 140 degrees".
	print "".

	WaitForOrbit(1.8, 2.2, 130, 140).

	TestHyperbolicDynamics().
	TestHyperbolicAnomalies().
	TestHyperbolicNodes().
}

// ------------------------------------------------------------
// TEST 6 — Hyperbola with node at periapsis
// ------------------------------------------------------------

if ResumeTest <= 6 {
	print "".
	print "------------------------------------------------------------".
	print "TEST 6: Hyperbolic node/periapsis coincidence".
	print "Required:".
	print "  e = 1.8 .. 2.2".
	print "  i = 40 .. 50 degrees".
	print "  w = approximately 0 degrees".
	print "".

	wait until (
		orbit:eccentricity >= 1.8
		and orbit:eccentricity <= 2.2
		and orbit:inclination >= 40
		and orbit:inclination <= 50
		and (
			orbit:argumentofperiapsis < 2
			or orbit:argumentofperiapsis > 358
		)
	).

	print "Orbit detected.".
	PrintOrbit().
	wait 1.

	TestHyperbolicDynamics().
	TestHyperbolicAnomalies().
	TestHyperbolicNodes().
}

print "".
print "########################################".
print "# TEST SUITE COMPLETE".
print "########################################".