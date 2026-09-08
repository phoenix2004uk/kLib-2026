{
	local RT_MODULE_NAME is "ModuleRTAntenna".

	function isModuleOmni {
		parameter module.
		return module:hasField("omni range").
	}

	function isModuleDish {
		parameter module.
		return module:hasField("dish range").
	}

	function createAntennaInterface {
		parameter module.
		local antennaPart is module:part.
		local partUid is antennaPart:uid.
		local isPartPresent is {
			for candidatePart in ship:parts if candidatePart:uid = partUid return true.
			return false.
		}.
		return lex(
			"name", antennaPart:name,
			"title", antennaPart:title,
			"tag", antennaPart:tag,
			"isOmni", isModuleOmni(module),
			"isDish", isModuleDish(module),
			"available", isPartPresent,
			"energy", {
				if not isPartPresent() return false.
				return module:getField("energy").
			},
			"status", {
				if not isPartPresent() return false.
				return module:getField("status").
			},
			"enable", {
				if not isPartPresent() return false.
				if not module:hasEvent("activate") return false.
				module:doEvent("activate").
				return true.
			},
			"disable", {
				if not isPartPresent() return false.
				if not module:hasEvent("deactivate") return false.
				module:doEvent("deactivate").
				return true.
			},
			"setTarget", {
				parameter dishTarget.
				if not isPartPresent() return false.
				if not isModuleDish(module) return false.
				module:setField("target", dishTarget).
				return true.
			}
		).
	}

	export(lex(
		"getAntennae", {
			parameter nameOrTag.
			local antennae is list().
			for antenna in ship:modulesNamed(RT_MODULE_NAME) if antenna:part:name = nameOrTag or antenna:part:title = nameOrTag or antenna:part:tag = nameOrTag antennae:add(createAntennaInterface(antenna)).
			return antennae.
		},
		"getAll", {
			local antennae is list().
			for antenna in ship:modulesNamed(RT_MODULE_NAME) antennae:add(createAntennaInterface(antenna)).
			return antennae.
		},
		"getAllDish", {
			local antennae is list().
			for antenna in ship:modulesNamed(RT_MODULE_NAME) if isModuleDish(antenna) antennae:add(createAntennaInterface(antenna)).
			return antennae.
		},
		"getAllOmni", {
			local antennae is list().
			for antenna in ship:modulesNamed(RT_MODULE_NAME) if isModuleOmni(antenna) antennae:add(createAntennaInterface(antenna)).
			return antennae.
		}
	)).
}