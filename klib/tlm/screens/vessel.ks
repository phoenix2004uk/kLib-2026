{
	local twr is import("tlm/twr-v1").

	local lock gravity to body:mu / (body:radius + altitude)^2.

	export(lex(
		"label", "VSL",
		"title", "Vessel",
		"fields", list(
			list("Name", { return ship:name. }),
			list("Status", { return status. }),
			list("Stage", { return stage:number. }),
			list("Mass", { return list(mass, ship:wetMass). }, "mass"),
			"-",
			list("Altitude (Sea Level)", { return altitude. }, "distance"),
			list("Altitude (Terrain)", { return alt:radar. }, "distance"),
			"-",
			list("Gravity", { return gravity. }, "acceleration"),
			list("Thrust", { return list(ship:thrust, availableThrust). }, "force"),
			list("TWR", { return list(twr:current(), twr:available()). }, "auto"),
			list("Acceleration", { return list(gravity * twr:current(), gravity * twr:available()). }, "acceleration")
		)
	)).
}