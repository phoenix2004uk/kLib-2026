{
	local TIME_DIVISORS is list(9201600,21600,3600,60).
	local DISTANCE_SUFFIXES is list("mm","cm","m","km","Mm","Gm","Tm").
	local FORCE_SUFFIXES is list("N","kN","MN").
	local MASS_SUFFIXES is list("g","kg","t","kt","Mt").
	local formatScalarDistance is {
		parameter value.
		local magnitude is abs(value).
		local unit is choose 0 if magnitude < .01
			else choose 1 if magnitude < 1
			else 2 + min(4, ceiling(log10(max(magnitude, 2e3) / 2e3) / 3)).
		local scaled is value / 10^max(unit - 3, 3 * unit - 6).
		return round(
			scaled,
			max(0, floor(log10(2e3 / max(abs(scaled), 20))))
		) + DISTANCE_SUFFIXES[unit].
	}.
	local formatScalarForce is {
		parameter value.
		local magnitude is abs(value).
		local unit is choose 0 if magnitude < 1
			else 1 + min(1, ceiling(log10(max(magnitude, 2e3) / 2e3) / 3)).
		local scaled is value / 10^(3 * (unit - 1)).
		return round(
			scaled,
			max(0, floor(log10(2e3 / max(abs(scaled), 20))))
		) + FORCE_SUFFIXES[unit].
	}.
	export(lex(
		"time", {
			parameter value.
			local magnitude is round(abs(value), 2).
			local result is "".
			for i in range(4) {
				local part is floor(magnitude / TIME_DIVISORS[i]).
				if result or part set result to result + part + "ydhm"[i] + " ".
				set magnitude to magnitude - part * TIME_DIVISORS[i].
			}
			return
				(choose "-" if value < 0 else "") +
				result +
				(choose "0" if result and magnitude < 10 else "") +
				"{0:0.00}s":format(magnitude).
		},
		"distance", formatScalarDistance,
		"force", formatScalarForce,
		"weight", formatScalarForce,
		"mass", {
			parameter value.
			local magnitude is abs(value).
			local unit is choose 0 if magnitude < .001
				else choose 1 if magnitude < 1
				else 2 + min(2, ceiling(log10(max(magnitude, 2e3) / 2e3) / 3)).
			local scaled is value / 10^(3 * (unit - 2)).
			return round(
				scaled,
				max(0, floor(log10(2e3 / max(abs(scaled), 20))))
			) + MASS_SUFFIXES[unit].
		},
		"speed", {
			parameter value.
			return formatScalarDistance(value) + "/s".
		},
		"acceleration", {
			parameter value.
			return formatScalarDistance(value) + "/s²".
		},
		"angle", {
			parameter value.
			return round(value, 4) + "°".
		}
	)).
}