{
	local STATE_FILE is "1:/state.run".
	local DATA_BUS_PATH is "1:/data/missionRunner/".
	local TMP_PATH is "1:/tmp/missionRunner/".
	local _IsRunnerFinished is{
		parameter runnerState.
		return runnerState:steps:length=0or runnerState:currentStep>=runnerState:steps:length.
	}.
	local _ExecuteEventLoop is{
		parameter runnerState,eventInterface.
		local enabled is list().
		for event in runnerState:events:values if event:enabled enabled:add(event).
		for event in enabled event:invoke(eventInterface).
	}.
	local _ClearTempState is{
		if exists(TMP_PATH)deletePath(TMP_PATH).
	}.
	local _SaveState is{
		parameter runnerState.
		local stateList is list(runnerState:currentStep,runnerState:nextStep).
		local events is runnerState:events.
		for eventName in events:keys if events[eventName]:enabled<>events[eventName]:default stateList:add(eventName).
		local stateData is stateList:join(",").
		_ClearTempState().
		local hStateFile is create(TMP_PATH+"state").
		if volume(1):freespace<stateData:length or not hStateFile:write(stateData)dmsg("[MissionRunner] WARNING! Insufficient volume space or write error! Mission state is not saved!",true).
		else movePath(TMP_PATH+"state",STATE_FILE).
		_ClearTempState().
	}.
	local _InvalidKeyName is{
		parameter name.
		return not name:matchesPattern("^[\w-]+$").
	}.
	local _StepNameExists is{
		parameter steps,stepName.
		for entry in steps if entry:name=stepName return true.
		return false.
	}.
	export(lex("create",{
		parameter constructorSteps is list().
		local runnerState is lex("steps",list(),"events",lex(),"commands",lex(),"currentStep",0,"nextStep",1,"errors",list(),"started",false,"bus",lex()).
		local interfaceToggleEvent is{
			parameter enabled,eventName.
			if runnerState:events:hasKey(eventName){
				set runnerState:events[eventName]:enabled to enabled.
				_SaveState(runnerState).
				return ApiOK().
			}
			return ApiFail("Event not found: "+eventName).
		}.
		local runnerInterface is lex(
			"next",{
				set runnerState:currentStep to runnerState:nextStep.
				set runnerState:nextStep to runnerState:nextStep+1.
				_SaveState(runnerState).
			},
			"end",{
				set runnerState:currentStep to runnerState:steps:length.
				set runnerState:nextStep to runnerState:steps:length+1.
				_SaveState(runnerState).
			},
			"disable",interfaceToggleEvent:bind(false),
			"enable",interfaceToggleEvent:bind(true),
			"current",{
				if _IsRunnerFinished(runnerState)return "Ended".
				if runnerState:started return runnerState:steps[runnerState:currentStep]:name.
				return "Starting/"+runnerState:steps[runnerState:currentStep]:name.
			},
			"share",{
				parameter tag,data.
				if not(data:isType("String")or data:isType("Scalar")or data:isType("Boolean"))return ApiFail("Mission runner bus does not support data type: "+data:typename).
				if _InvalidKeyName(tag)return ApiFail("Mission runner bus tag '"+tag+"' has invalid characters").
				if runnerState:bus:hasKey(tag)set runnerState:bus[tag]to data.
				else runnerState:bus:add(tag,data).
				local type is"S".
				if data:isType("Boolean"){
					set type to"B".
					set data to choose 1if data else 0.
				}
				else if data:isType("Scalar")set type to"N".
				local busData is type+data:toString.
				_ClearTempState().
				if volume(1):freespace<busData:length or not create(TMP_PATH+"data/"+tag):write(busData)dmsg("[MissionRunner] WARNING! Insufficient volume space or write error! Data bus tag '"+tag+"' is not saved!",true).
				else movePath(TMP_PATH+"data/"+tag,DATA_BUS_PATH+tag).
				_ClearTempState().
				return ApiOK().
			},
			"fetch",{
				parameter tag.
				if runnerState:bus:hasKey(tag)return runnerState:bus[tag].
				return"".
			}
		).
		local eventInterface is lex(
			"enable",runnerInterface:enable,
			"disable",runnerInterface:disable,
			"current",runnerInterface:current,
			"fetch",runnerInterface:fetch
		).
		local runnerInstance is lex().
		runnerInterface:add("invoke",{
			parameter commandName.
			if runnerState:commands:hasKey(commandName)return ApiOK(runnerState:commands[commandName](eventInterface)).
			return ApiFail("Command not found: "+commandName).
		}).
		runnerInterface:add("tick",{
			_ExecuteEventLoop(runnerState,eventInterface).
		}).
		eventInterface:add("invoke",runnerInterface:invoke).
		runnerInstance:add("steps",{
			parameter newSteps.
			for entry in newSteps{
				local name is entry[0].
				if _InvalidKeyName(name)runnerState:errors:add("Mission step '"+name+"' has invalid characters").
				else if name="Starting" or name="Ended" runnerState:errors:add("Mission step '"+name+"' is reserved").
				else if _StepNameExists(runnerState:steps,name)runnerState:errors:add("Mission step '"+name+"' already exists").
				else runnerState:steps:add(lex("name",name,"run",entry[1])).
			}
			return runnerInstance.
		}).
		runnerInstance:add("events",{
			parameter newEvents.
			for entry in newEvents{
				local name is entry[0].
				local enabled is choose entry[2]if entry:length>2else true.
				if _InvalidKeyName(name)runnerState:errors:add("Mission event '"+name+"' has invalid characters").
				else if runnerState:events:hasKey(name)runnerState:errors:add("Mission event '"+name+"' already exists").
				else runnerState:events:add(name,lex("enabled",enabled,"default",enabled,"invoke",entry[1])).
			}
			return runnerInstance.
		}).
		runnerInstance:add("commands",{
			parameter newCommands.
			for entry in newCommands{
				local name is entry[0].
				if _InvalidKeyName(name)runnerState:errors:add("Mission command '"+name+"' has invalid characters").
				else if runnerState:commands:hasKey(name)runnerState:errors:add("Mission command '"+name+"' already exists").
				else runnerState:commands:add(name,entry[1]).
			}
			return runnerInstance.
		}).
		runnerInstance:add("start",{
			if exists(STATE_FILE){
				local stateList is open(STATE_FILE):readall:string:split(",").
				if stateList:length<2 runnerState:errors:add("Saved mission state is malformed").
				else {
					set runnerState:currentStep to stateList[0]:toScalar(-1).
					set runnerState:nextStep to stateList[1]:toScalar(-1).
					if runnerState:currentStep<>stateList[0]:toScalar(0)or runnerState:nextStep<>stateList[1]:toScalar(0)runnerState:errors:add("Failed to load current/next step from saved state").
					for eventName in stateList:sublist(2,stateList:length-2)
						if runnerState:events:hasKey(eventName)
							set runnerState:events[eventName]:enabled to not runnerState:events[eventName]:default.
						else dmsg("[MissionRunner] WARNING! Attempted to restore state for mission event: "+eventName,true).
				}
			}
			if exists(DATA_BUS_PATH){
				local bus is lex().
				local dataFiles is open(DATA_BUS_PATH):lex.
				for tag in dataFiles:keys{
					local fileContent is dataFiles[tag]:readall:string.
					local type is fileContent[0].
					local data is fileContent:remove(0,1).
					local valid is type="S".
					local parsedData is data.
					if type="B"{
						set valid to data="1"or data="0".
						set parsedData to data="1".
					}
					else if type="N"{
						set parsedData to data:toScalar(0).
						set valid to parsedData=data:toScalar(1).
					}
					if valid bus:add(tag,parsedData).
					else runnerState:errors:add("Failed to parse tag '"+tag+"' as type '"+type+"': "+data).
				}
				set runnerState:bus to bus.
			}
			if runnerState:errors:length>0{
				notify("Mission failed to start").
				dmsg("[MissionRunner] Mission cannot start due to one or more errors:",true).
				for error in runnerState:errors dmsg(" * "+error,true).
				return false.
			}
			set runnerState:started to true.
			until _IsRunnerFinished(runnerState){
				runnerState:steps[runnerState:currentStep]:run(runnerInterface).
				_ExecuteEventLoop(runnerState,eventInterface).
				wait 0.
			}
			return true.
		}).
		runnerInstance:steps(constructorSteps).
		return runnerInstance.
	})).
}