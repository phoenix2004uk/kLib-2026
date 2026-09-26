export(lex(
	"label", "OBT",
	"title", "Orbital",
	"fields", list(
		list("Apoapsis Altitude", { return choose apoapsis if obt:eccentricity < 1 else "Undefined". }, "distance"),
		list("Periapsis Altitude", { return periapsis. }, "distance"),
		list("Semi-Major axis", { return obt:semiMajorAxis. }, "distance"),
		"-",
		list("Time to Apoapsis", { return choose eta:apoapsis if obt:eccentricity < 1 else "Undefined". }, "time"),
		list("Time to Periapsis", { return eta:periapsis. }, "time"),
		list("Orbit Period", { return choose obt:period if obt:eccentricity < 1 else "Undefined". }, "time"),
		"-",
		list("Inclination", { return obt:inclination. }),
		list("Eccentricity", { return obt:eccentricity. }),
		list("Orbital Speed", { return velocity:orbit:mag. },"speed"),
		list("Longitude of AN", { return ship:orbit:lan. }, "angle"),
		list("Argument of Periapsis", { return ship:orbit:argumentofperiapsis. }, "angle")
	)
)).