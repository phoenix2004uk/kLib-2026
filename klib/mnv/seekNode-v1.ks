{
	local SEEK_MAGNITUDE_HIGH is 2.
	local SEEK_MAGNITUDE_LOW is -2.
	local DELTA is list(0, 1, -1).

	function create_base_data {
		parameter mnv.
		return list(time:seconds + mnv:eta, mnv:radialout, mnv:normal, mnv:prograde).
	}.

	function create_seek_matrix {
		parameter tuning_parameters.
		local seek_matrix is list().
		local seek_unique is uniqueset().
		local var_time is tuning_parameters:contains("time").
		local var_radial is tuning_parameters:contains("radial").
		local var_normal is tuning_parameters:contains("normal").
		local var_prograde is tuning_parameters:contains("prograde").
		for i in range(0,81) {
			local seek_data is list(
				choose DELTA[mod(floor(i/27)+3,3)] if var_time else 0,
				choose DELTA[mod(floor(i/9)+3,3)] if var_radial else 0,
				choose DELTA[mod(floor(i/3)+3,3)] if var_normal else 0,
				choose DELTA[mod(i+3,3)] if var_prograde else 0
			).
			local unique_data is seek_data:join(",").
			if not seek_unique:contains(unique_data) {
				seek_unique:add(unique_data).
				seek_matrix:add(seek_data).
			}
		}
		return seek_matrix.
	}.

	function update_maneuver {
		parameter mnv, base_data, seek_data, magnitude.
		
		set mnv:eta to base_data[0] + (seek_data[0]*magnitude) - time:seconds.
		set mnv:radialout to base_data[1] + (seek_data[1]*magnitude).
		set mnv:normal to base_data[2] + (seek_data[2]*magnitude).
		set mnv:prograde to base_data[3] + (seek_data[3]*magnitude).
		return mnv.
	}.

	function seek_step {
		parameter mnv, seek_matrix, fitness_function, magnitude.

		local best_index is -1.
		local best_fitness is 3e30.

		until best_index = 0 {
			set best_index to 0.
			local base_data is create_base_data(mnv).
			local iter is seek_matrix:iterator.
			until not iter:next {
				update_maneuver(mnv, base_data, iter:value, magnitude).
				local fitness_score is fitness_function(mnv).
				if abs(fitness_score) < best_fitness {
					set best_fitness to abs(fitness_score).
					set best_index to iter:index.
				}
			}
			update_maneuver(mnv, base_data, seek_matrix[best_index], magnitude).
			wait 0.
		}
	}.

	// mnv: ManeuverNode
	// tuning_parameters: list containing parameters to seek -> list("time", "radial", "normal", "prograde")
	// fitness_function: fitness delegate -> {parameter mnv.} returns a scalar score where 0 is best.
	// seek_magnitude_start, seek_magnitude_end: exponent scale used on parameters for each seeking step -> 2 = 10^2 or 100, -2 = 10^-2 or 0.01
	function seekNode {
		parameter mnv, tuning_parameters, fitness_function, seek_magnitude_start is SEEK_MAGNITUDE_HIGH, seek_magnitude_end is SEEK_MAGNITUDE_LOW.

		local seek_matrix is create_seek_matrix(tuning_parameters).

		for seek_exponent in range(seek_magnitude_start, seek_magnitude_end-1) {
			local magnitude is 10^seek_exponent.
			seek_step(mnv, seek_matrix, fitness_function, magnitude).
		}
	}

	export(seekNode@).
}