{
	local RT_MODULE_NAME is "ModuleRTAntenna".
	local RT_TARGET_FIELD is "target".
	local RT_ENERGY_FIELD is "energy".
	local RT_STATUS_FIELD is "status".
	local RT_OMNI_RANGE_FIELD is "omni range".
	local RT_DISH_RANGE_FIELD is "dish range".
	local RT_ENABLE_EVENT is "activate".
	local RT_DISABLE_EVENT is "deactivate".

	function isPartPresent {
		parameter partUid.

		for candidatePart in ship:parts if candidatePart:uid = partUid return true.

		return false.
	}

	function isModuleOmni {
		parameter module.

		return module:hasField(RT_OMNI_RANGE_FIELD).
	}

	function isModuleDish {
		parameter module.

		return module:hasField(RT_DISH_RANGE_FIELD).
	}

	// function getOmniRange {
	// 	parameter module.

	// 	if isModuleOmni(module) return module:getField(RT_OMNI_RANGE_FIELD).
	// 	return false.
	// }

	// function getDishRange {
	// 	parameter module.

	// 	if isModuleDish(module) return module:getField(RT_DISH_RANGE_FIELD).
	// 	return false.
	// }

	function getAntennaEnergy {
		parameter module, partUid.

		if not isPartPresent(partUid) return false.

		return module:getField(RT_ENERGY_FIELD).
	}

	function getAntennaStatus {
		parameter module, partUid.

		if not isPartPresent(partUid) return false.

		return module:getField(RT_STATUS_FIELD).
	}

	function enableAntenna {
		parameter module, partUid.

		if not isPartPresent(partUid) return false.

		if not module:hasEvent(RT_ENABLE_EVENT) return false.
		module:doEvent(RT_ENABLE_EVENT).
		return true.
	}

	function disableAntenna {
		parameter module, partUid.

		if not isPartPresent(partUid) return false.

		if not module:hasEvent(RT_DISABLE_EVENT) return false.
		module:doEvent(RT_DISABLE_EVENT).
		return true.
	}

	function setDishTarget {
		parameter module, partUid, dishTarget.

		if not isPartPresent(partUid) return false.

		if not isModuleDish(module) return false.
		module:setField(RT_TARGET_FIELD, dishTarget).
		return true.
	}

	function createAntennaInterface {
		parameter module.

		local partUid is module:part:uid.

		return lex(
			"name", module:part:name,
			"title", module:part:title,
			"tag", module:part:tag,
			"isOmni", isModuleOmni(module),
			"isDish", isModuleDish(module),
			// "omniRange", getOmniRange(module),
			// "dishRange", getDishRange(module),
			"available", isPartPresent@:bind(partUid),
			"energy", getAntennaEnergy@:bind(module, partUid),
			"status", getAntennaStatus@:bind(module, partUid),
			"enable", enableAntenna@:bind(module, partUid),
			"disable", disableAntenna@:bind(module, partUid),
			"setTarget", setDishTarget@:bind(module, partUid)
		).
	}

	function getAntennaeNamed {
		parameter nameOrTag.

		local antennae is list().
		for antenna in ship:modulesNamed(RT_MODULE_NAME) {
			if antenna:part:name = nameOrTag
			or antenna:part:title = nameOrTag
			or antenna:part:tag = nameOrTag {
				antennae:add(createAntennaInterface(antenna)).
			}
		}

		return antennae.
	}

	function getAllAntennae {
		local antennae is list().
		for antenna in ship:modulesNamed(RT_MODULE_NAME) {
			antennae:add(createAntennaInterface(antenna)).
		}

		return antennae.
	}

	function getAllDish {
		local antennae is list().
		for antenna in ship:modulesNamed(RT_MODULE_NAME) {
			if isModuleDish(antenna) {
				antennae:add(createAntennaInterface(antenna)).
			}
		}

		return antennae.
	}

	function getAllOmni {
		local antennae is list().
		for antenna in ship:modulesNamed(RT_MODULE_NAME) {
			if isModuleOmni(antenna) {
				antennae:add(createAntennaInterface(antenna)).
			}
		}

		return antennae.
	}

	export(lex(
		"getAntennae", getAntennaeNamed@,
		"getAll", getAllAntennae@,
		"getAllDish", getAllDish@,
		"getAllOmni", getAllOmni@
	)).
}