wait until ship:unpacked.
wait 1.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
set ship:control:pilotmainthrottle to 0.
sas off.
set config:ipu to 200.
clearScreen.
{
	local _kDebug is core:tag="debug",
		_kLibRoots is list("0:/klib/","0:/klib-nrm/","0:/klib-min/"),
		_kUid is core:part:uid,
		_kTmp is"0:/"+_kUid+".ksm",
		_kBestTmp is"0:/"+_kUid+"-b.ksm",
		_kMapPath is"1:/kldr-map",
		_kDmsgLogFile is"0:/dmsg/"+_kUid+"-"+ship:name+".log",
		_kDmsgBufferFile is"1:/dmsg.log",
		_kGeneration is 0,
		_kMap is lex(),
		_kExportStack is stack(),
		_kLoadStack is stack(),
		_kLoaded is lex(),
		_kParents is lex(),
		_kChildren is lex(),
		_kDmsgArchiveReady is false.
	local lock _kConnected to homeConnection:isconnected.
	global dmsg is{
		parameter _kMessage,_kPrint is false.
		if _kPrint print _kMessage.
		local _kMet is round(missionTime,6):tostring.
		if _kMet:find(".")<0 set _kMet to _kMet+".".
		set _kMet to(_kMet+"000000"):substring(0,_kMet:find(".")+7).
		set _kMessage to"[MET "+_kMet:padleft(14)+"] "+_kMessage:tostring.
		if _kConnected{
			if not _kDmsgArchiveReady{
				if not exists(_kDmsgLogFile)create(_kDmsgLogFile).
				set _kDmsgArchiveReady to true.
			}
			if exists(_kDmsgBufferFile){
				for _kLine in open(_kDmsgBufferFile):readall log _kLine to _kDmsgLogFile.
				deletePath(_kDmsgBufferFile).
			}
			log _kMessage to _kDmsgLogFile.
		}
		else if volume(1):freespace-_kMessage:length>500 log _kMessage to _kDmsgBufferFile.
	}.
	global ApiOK is{
		parameter _kValue is true,_kMessage is"".
		return lex("ok",true,"val",_kValue,"msg",_kMessage).
	}.
	global ApiFail is{
		parameter _kMessage,_kValue is false.
		return lex("ok",false,"val",_kValue,"msg",_kMessage).
	}.
	global export is{
		parameter _kObject.
		_kExportStack:push(_kObject).
	}.
	global import is{
		parameter _kLibName.
		local _kParent is choose _kLoadStack:peek if not _kLoadStack:empty else"@".
		if not _kChildren:haskey(_kParent)set _kChildren[_kParent] to uniqueSet().
		if not _kParents:haskey(_kLibName)set _kParents[_kLibName] to uniqueSet().
		_kChildren[_kParent]:add(_kLibName).
		_kParents[_kLibName]:add(_kParent).
		if _kLoaded:haskey(_kLibName)return _kLoaded[_kLibName].
		if _kLoadStack:contains(_kLibName)_kPanic("Error! Circular import: "+_kLibName).
		local _kPath is _kEnsureLib(_kLibName),
			_kExportDepth is _kExportStack:length.
		_kLoadStack:push(_kLibName).
		runPath(_kPath).
		_kLoadStack:pop().
		if _kExportStack:length<>_kExportDepth+1 _kPanic("Error! Invalid export: "+_kLibName).
		local _kObject is _kExportStack:pop().
		set _kLoaded[_kLibName] to _kObject.
		return _kObject.
	}.
	global purge is{
		parameter _kLibName.
		if not _kLoaded:haskey(_kLibName)return ApiFail("Library not imported: "+_kLibName).
		if _kParents:haskey(_kLibName){
			local _kBlocking is _kParents[_kLibName]:copy.
			_kBlocking:remove("@").
			if not _kBlocking:empty return ApiFail("Library still has parents",_kBlocking).
			_kParents[_kLibName]:remove("@").
			if _kChildren:haskey("@")_kChildren["@"]:remove(_kLibName).
		}
		local _kCount is _kDropLib(_kLibName).
		_kSaveMap().
		return ApiOK(_kCount).
	}.
	function _kPanic{
		parameter _kMessage.
		dmsg(_kMessage,true).
		shutdown.
	}
	function _kSaveMap{
		writeJSON(list(_kGeneration,_kMap),_kMapPath).
	}
	function _kHasExec{
		parameter _kBase.
		return exists(_kBase+".ks")or exists(_kBase+".ksm").
	}
	function _kDeleteExec{
		parameter _kBase.
		deletePath(_kBase+".ks").
		deletePath(_kBase+".ksm").
	}
	function _kLibPath{
		parameter _kLibName.
		return"1:/klib/"+_kLibName+"-"+abs(_kMap[_kLibName]).
	}
	function _kCopySource{
		parameter _kSrc,_kDst.
		_kDeleteExec(_kDst).
		copyPath(_kSrc+".ks",_kDst+".ks").
	}
	function _kCopyBest{
		parameter _kName,_kDst,_kRoots.
		local _kBestSize is -1,
			_kBestPath is"",
			_kBestExt is"".
		deletePath(_kTmp).
		deletePath(_kBestTmp).
		for _kRoot in _kRoots{
			local _kSrc is _kRoot+_kName+".ks".
			if exists(_kSrc){
				local _kSize is open(_kSrc):size.
				if _kBestSize<0 or _kSize<_kBestSize{
					set _kBestSize to _kSize.
					set _kBestPath to _kSrc.
					set _kBestExt to".ks".
				}
				compile _kSrc to _kTmp.
				set _kSize to open(_kTmp):size.
				if _kSize<_kBestSize{
					movePath(_kTmp,_kBestTmp).
					set _kBestSize to _kSize.
					set _kBestPath to _kBestTmp.
					set _kBestExt to".ksm".
				}
				else deletePath(_kTmp).
			}
		}
		if _kBestSize<0 return false.
		_kDeleteExec(_kDst).
		copyPath(_kBestPath,_kDst+_kBestExt).
		deletePath(_kBestTmp).
		return true.
	}
	function _kEnsureLib{
		parameter _kLibName.
		local _kSource is"0:/klib/"+_kLibName,
			_kLocal is"".
		if _kMap:haskey(_kLibName){
			set _kLocal to _kLibPath(_kLibName).
			if _kHasExec(_kLocal){
				if _kDebug and _kConnected{
					if not exists(_kSource+".ks")_kPanic("Error! No library source: "+_kLibName).
					_kCopySource(_kSource,_kLocal).
					if _kMap[_kLibName]>0{
						set _kMap[_kLibName] to -_kMap[_kLibName].
						_kSaveMap().
					}
				}
				else if not _kDebug and _kMap[_kLibName]<0 and _kConnected and _kCopyBest(_kLibName,_kLocal,_kLibRoots){
					set _kMap[_kLibName] to -_kMap[_kLibName].
					_kSaveMap().
				}
				return _kLocal.
			}
			_kMap:remove(_kLibName).
		}
		if not _kConnected _kPanic("Error! Missing library: "+_kLibName+char(10)+"No KSC Connection").
		if _kDebug and not exists(_kSource+".ks")_kPanic("Error! No library source: "+_kLibName).
		set _kGeneration to _kGeneration+1.
		set _kMap[_kLibName] to choose -_kGeneration if _kDebug else _kGeneration.
		set _kLocal to _kLibPath(_kLibName).
		if _kDebug _kCopySource(_kSource,_kLocal).
		else if not _kCopyBest(_kLibName,_kLocal,_kLibRoots){
			_kMap:remove(_kLibName).
			_kPanic("Error! No library: "+_kLibName).
		}
		_kSaveMap().
		return _kLocal.
	}
	function _kDropLib{
		parameter _kLibName.
		local _kCount is 1.
		if _kChildren:haskey(_kLibName){
			for _kChild in _kChildren[_kLibName]:copy if _kParents:haskey(_kChild){
				_kParents[_kChild]:remove(_kLibName).
				if _kParents[_kChild]:empty set _kCount to _kCount+_kDropLib(_kChild).
			}
			_kChildren:remove(_kLibName).
		}
		if _kParents:haskey(_kLibName)_kParents:remove(_kLibName).
		if _kLoaded:haskey(_kLibName)_kLoaded:remove(_kLibName).
		if _kMap:haskey(_kLibName){
			_kDeleteExec(_kLibPath(_kLibName)).
			_kMap:remove(_kLibName).
		}
		return _kCount.
	}
	dmsg("[kldr] Boot "+ship:tostring+" tag="+char(34)+core:tag+char(34)+" at "+time:seconds).
	local _kMissionName is choose ship:name if _kDebug or core:tag=""else core:tag,
		_kMissionSource is"0:/missions/"+_kMissionName,
		_kMain is"1:/main".
	if exists(_kMapPath){
		local _kState is readJSON(_kMapPath).
		set _kGeneration to _kState[0].
		set _kMap to _kState[1].
	}
	if _kMap:length>0 and not exists("1:/klib"){
		_kMap:clear().
		_kSaveMap().
	}
	if status="PRELAUNCH"{
		if not _kConnected _kPanic("Error! No KSC Connection").
		if not exists(_kMissionSource+".ks")_kPanic("Error! No mission script: "+_kMissionName).
	}
	if _kDebug{
		if _kConnected and exists(_kMissionSource+".ks")_kCopySource(_kMissionSource,_kMain).
	}
	else if status="PRELAUNCH" or(not _kHasExec(_kMain)and _kConnected and exists(_kMissionSource+".ks"))_kCopyBest(_kMissionName,_kMain,list("0:/missions/")).
	if not _kHasExec(_kMain)_kPanic("Error! No local mission script").
}
runPath("1:/main").