--
-- 海鳗插件、常用函数库、UI 界面组件
-- by：海鳗@电信2区荻花宫
--

---------------------------------------------------------------------
-- 多语言处理
---------------------------------------------------------------------
local function _HM_GetLang()
	local _, _, szLang = GetVersion()
	local t0 = LoadLUAData("interface\\HM\\lang\\default.lua") or {}
	local t1 = LoadLUAData("interface\\HM\\lang\\" .. szLang .. ".lua") or {}
	for k, v in pairs(t0) do
		if not t1[k] then
			t1[k] = v
		end
	end
	setmetatable(t1, {
		__index = function(t, k) return k end,
		__call = function(t, k, ...) return string.format(t[k], ...) end,
	})
	return t1
end
_L = _HM_GetLang()

---------------------------------------------------------------------
-- 本地函数和变量
---------------------------------------------------------------------
local _HM = {
	dwVersion = 0x2020b01,
	szBuildDate = "20140123",
	szTitle = _L["HM, JX3 Plug-in Collection"],
	szShort = _L["HM Plug"],
	szIniFile = "interface\\HM\\ui\\HM.ini",
	tClass = { _L["General"], _L["Target"], _L["Battle"] },
	tItem = { {}, {}, {} },
	tMenu = {},
	tEvent = {},
	tHotkey = {},
	tDelayCall = {},
	tBreatheCall = {},
	tCustomUpdateCall = {},
	tTempTarget = {},
	tSelect = {},
	tRequest = {},
	tBuffCache = {},
	tSkillCache = {},
	aNpc = {},
	aPlayer = {},
	aDoodad = {},
	nDebug = 1,
}

-------------------------------------
-- 设置面板开关、初始化
-------------------------------------
-- open
_HM.OpenPanel = function(bDisableSound)
	local frame = Station.Lookup("Normal/HM") or Wnd.OpenWindow(_HM.szIniFile, "HM")
	frame:Show()
	frame:BringToTop()
	if not bDisableSound then
		if HM_About and HM_About.bPlayOpen
			and (not _HM.nPlayOpen or (GetLogicFrameCount() - _HM.nPlayOpen) > 57600)
		then
			PlaySound(SOUND.UI_SOUND, "interface\\HM\\ui\\opening.wav")
			_HM.nPlayOpen = GetLogicFrameCount()
		else
			PlaySound(SOUND.UI_SOUND, g_sound.OpenFrame)
		end
	end
	return frame
end

-- close
_HM.ClosePanel = function(bRealClose)
	local frame = Station.Lookup("Normal/HM")
	if frame then
		if not bRealClose then
			frame:Hide()
		else
			local button = Player_GetFrame():Lookup("HM_Button")
			if button then
				button:Destroy()
			end
			Wnd.CloseWindow(frame)
			_HM.frame = nil
		end
		PlaySound(SOUND.UI_SOUND, g_sound.CloseFrame)
	end
end

-- toggle
_HM.TogglePanel = function()
	if _HM.frame and _HM.frame:IsVisible() then
		_HM.ClosePanel()
	else
		_HM.OpenPanel()
	end
end

-- initlization
_HM.Init = function()
	local pFrame = Player_GetFrame()
	local hFrame = _HM.OpenPanel(true)
	-- button
	local button = pFrame:Lookup("HM_Button")
	if not button then
		button = hFrame:Lookup("Btn_Menu")
		button:SetName("HM_Button")
		button:ChangeRelation(pFrame, true, true)
		button.OnMouseEnter = function()
			local nX, nY = this:GetAbsPos()
			local nW, nH = this:GetSize()
			local szTip = GetFormatText("<" .. _HM.szShort .. ">\n", 101) .. GetFormatText(_L["Click to open setting panel!"], 106)
			OutputTip(szTip, 400, {nX, nY, nW, nH})
		end
		button.OnLButtonClick = _HM.TogglePanel
		button.OnRButtonClick = _HM.TogglePanel
		button:Show()
	else
		return
	end
	--  hide
	hFrame:Hide()
	-- hotkey
	Hotkey.AddBinding("HM_Total", _L["Open/Close setting panel"], _HM.szTitle, _HM.TogglePanel, nil)
	for _, v in ipairs(_HM.tHotkey) do
		Hotkey.AddBinding(v.szName, v.szTitle, "", v.fnAction, nil)
	end
	-- hook system
	_HM.HookPlayerMenu()
end

-------------------------------------
-- 杂项本地函数
-------------------------------------
-- handle event
_HM.EventHandler = function(szEvent)
	local tEvent = _HM.tEvent[szEvent]
	if tEvent then
		for k, v in pairs(tEvent) do
			local res, err = pcall(v)
			if not res then
				HM.Debug("EVENT#" .. szEvent .. "." .. k .." ERROR: " .. err)
			end
		end
	end
end

-- select player as target temporary
_HM.SetTempTarget = function()
	if _HM.nTempFrame and _HM.nTempFrame > GetLogicFrameCount() then
		return
	end
	-- check current target
	local me, bApply = GetClientPlayer(), false
	if not me then return end
	if not _HM.nOrigTarget then
		if table.getn(_HM.tTempTarget) > 0 then
			bApply = true
		end
	else
		local dwType, dwID = me.GetTarget()
		if dwType ~= TARGET.PLAYER then
			bApply = true
		else
			local tar = GetPlayer(dwID)
			if not tar or tar.GetKungfuMount() ~= nil then
				bApply = true
			end
		end
	end
	if bApply == true then
		while true do
			if table.getn(_HM.tTempTarget) == 0 or me.bFightState then
				if _HM.nOrigTarget and _HM.nOrigTarget ~= 0 then
					HM.SetTarget(_HM.nOrigTarget)
					HM.Sysmsg(_L("Restore target [#%d]",  _HM.nOrigTarget))
					_HM.nOrigTarget = nil
				end
				break
			end
			local tar = GetPlayer(table.remove(_HM.tTempTarget, 1))
			if tar and tar.GetKungfuMount() == nil then
				if not _HM.nOrigTarget then
					_, _HM.nOrigTarget = me.GetTarget()
				end
				HM.Sysmsg(_L("Temporarily switch target [#%d]", tar.szName))
				HM.SetTarget(TARGET.PLAYER, tar.dwID)
				break
			end
		end
	end
	_HM.nTempFrame = GetLogicFrameCount() + 8
end

-- get channel header
_HM.tTalkChannelHeader = {
	[PLAYER_TALK_CHANNEL.NEARBY] = "/s ",
	[PLAYER_TALK_CHANNEL.FRIENDS] = "/o ",
	[PLAYER_TALK_CHANNEL.TONG_ALLIANCE] = "/a ",
	[PLAYER_TALK_CHANNEL.RAID] = "/t ",
	[PLAYER_TALK_CHANNEL.BATTLE_FIELD] = "/b ",
	[PLAYER_TALK_CHANNEL.TONG] = "/g ",
	[PLAYER_TALK_CHANNEL.SENCE] = "/y ",
	[PLAYER_TALK_CHANNEL.FORCE] = "/f ",
	[PLAYER_TALK_CHANNEL.CAMP] = "/c ",
	[PLAYER_TALK_CHANNEL.WORLD] = "/h ",
}

-- parse faceicon in talking message
_HM.ParseFaceIcon = function(t)
	if not _HM.tFaceIcon then
		_HM.tFaceIcon = {}
		for i = 1, g_tTable.FaceIcon:GetRowCount() do
			local tLine = g_tTable.FaceIcon:GetRow(i)
			_HM.tFaceIcon[tLine.szCommand] = true
		end
	end
	local t2 = {}
	for _, v in ipairs(t) do
		if v.type ~= "text" then
			if v.type == "faceicon" then
				v.type = "text"
			end
			table.insert(t2, v)
		else
			local nOff, nLen = 1, string.len(v.text)
			while nOff <= nLen do
				local szFace = nil
				local nPos = StringFindW(v.text, "#", nOff)
				if not nPos then
					nPos = nLen
				else
					for i = nPos + 6, nPos + 2, -2 do
						if i <= nLen then
							local szTest = string.sub(v.text, nPos, i)
							if _HM.tFaceIcon[szTest] then
								szFace = szTest
								nPos = nPos - 1
								break
							end
						end
					end
				end
				if nPos >= nOff then
					table.insert(t2, { type = "text", text = string.sub(v.text, nOff, nPos) })
					nOff = nPos + 1
				end
				if szFace then
					table.insert(t2, { type = "text", text = szFace })
					nOff = nOff + string.len(szFace)
				end
			end
		end
	end
	return t2
end

-- register conflict checker
_HM.RegisterConflictCheck = function(fnAction)
	_HM.tConflict = _HM.tConflict or {}
	table.insert(_HM.tConflict, fnAction)
end

-- fetch menu item traverse
_HM.FetchMenuItem = function(tData, szOption)
	if tData.szOption == szOption then
		return tData
	end
	for _, v in ipairs(tData) do
		local t = _HM.FetchMenuItem(v, szOption)
		if t then
			return t
		end
	end
end

-- callback of apply point
_HM.tApplyPointKey = {}
_HM.ApplyPointCallback = function(data, nX, nY)
	if not nX or (nX > 0 and nX < 0.00001 and nY > 0 and nY < 0.00001) then
		nX, nY = nil, nil
	else
		nX, nY = Station.AdjustToOriginalPos(nX, nY)
	end
	if data.szKey then
		_HM.tApplyPointKey[data.szKey] = nil
	end
	local res, err = pcall(data.fnAction, nX, nY)
	if not res then
		HM.Debug("ApplyScreenPoint ERROR: " .. err)
	end
end

-- channel skill
_HM.tChannelSkill = {
	[300] = 80, [368] = 80, [565] = 48, [567] = 160, [570] = 80, [1645] = 84,
	[2233] = 80, [2235] = 128, [2589] = 96, [2636] = 80, [2674] = 8, [2707] = 48,
	[2724] = 40, [3093] = 40, [3100] = 48, [3961] = 120, [3985] = 114, [5268] = 40,
	[5270] = 153, [6444] = 40, [6675] = 80, [7967] = 96, [7968] = 96,
}

-- broken skill
_HM.tNonBrokenSkill = {
	[62] = true, [72] = true, [173] = true, [832] = true, [841] = true, [847] = true,
	[854] = true, [855] = true, [961] = true, [974] = true, [986] = true, [1019] = true,
	[1036] = true, [1039] = true, [1041] = true, [1045] = true, [1047] = true, [1049] = true,
	[1051] = true, [1055] = true, [1056] = true, [1067] = true, [1081] = true, [1133] = true,
	[1134] = true, [1135] = true, [1136] = true, [1138] = true, [1139] = true, [1140] = true,
	[1142] = true, [1143] = true, [1144] = true, [1146] = true, [1147] = true, [1148] = true,
	[1182] = true, [1184] = true, [1193] = true, [1194] = true, [1245] = true, [1248] = true,
	[1249] = true, [1294] = true, [1328] = true, [1330] = true, [1332] = true, [1340] = true,
	[1342] = true, [1344] = true, [1347] = true, [1348] = true, [1349] = true, [1351] = true,
	[1357] = true, [1362] = true, [1375] = true, [1381] = true, [1413] = true, [1443] = true,
	[1448] = true, [1452] = true, [1482] = true, [1492] = true, [1501] = true, [1514] = true,
	[1542] = true, [1546] = true, [1547] = true, [1560] = true, [1562] = true, [1624] = true,
	[1629] = true, [1630] = true, [1631] = true, [1632] = true, [1634] = true, [1635] = true,
	[1639] = true, [1640] = true, [1641] = true, [1645] = true, [1652] = true, [1680] = true,
	[1742] = true, [1767] = true, [1770] = true, [1778] = true, [1804] = true, [1821] = true,
	[1953] = true, [1960] = true, [1963] = true, [1970] = true, [1977] = true, [1979] = true,
	[1996] = true, [2005] = true, [2008] = true, [2010] = true, [2013] = true, [2015] = true,
	[2026] = true, [2029] = true, [2031] = true, [2036] = true, [2038] = true, [2041] = true,
	[2048] = true, [2050] = true, [2051] = true, [2054] = true, [2080] = true, [2094] = true,
	[2105] = true, [2118] = true, [2141] = true, [2157] = true, [2193] = true, [2198] = true,
	[2199] = true, [2203] = true, [2208] = true, [2235] = true, [2255] = true, [2259] = true,
	[2271] = true, [2279] = true, [2282] = true, [2285] = true, [2289] = true, [2290] = true,
	[2296] = true, [2311] = true, [2312] = true, [2346] = true, [2347] = true, [2348] = true,
	[2349] = true, [2360] = true, [2361] = true, [2362] = true, [2366] = true, [2368] = true,
	[2370] = true, [2371] = true, [2510] = true, [2514] = true, [2522] = true, [2531] = true,
	[2532] = true, [2533] = true, [2534] = true, [2535] = true, [2548] = true, [2777] = true,
	[2782] = true, [2798] = true, [2809] = true, [2812] = true, [2824] = true, [2829] = true,
	[2874] = true, [2879] = true, [2880] = true, [2881] = true, [2882] = true, [2883] = true,
	[2885] = true, [2886] = true, [2887] = true, [2889] = true, [2890] = true, [2892] = true,
	[2901] = true, [3011] = true, [3022] = true, [3025] = true, [3033] = true, [3100] = true,
	[3128] = true, [3129] = true, [3134] = true, [3135] = true, [3137] = true, [3143] = true,
	[3149] = true, [3164] = true, [3166] = true, [3173] = true, [3177] = true, [3179] = true,
	[3180] = true, [3182] = true, [3196] = true, [3197] = true, [3246] = true, [3250] = true,
	[3254] = true, [3256] = true, [3257] = true, [3318] = true, [3365] = true, [3377] = true,
	[3392] = true, [3398] = true, [3504] = true, [3530] = true, [3531] = true, [3533] = true,
	[3535] = true, [3536] = true, [3539] = true, [3547] = true, [3549] = true, [3564] = true,
	[3566] = true, [3571] = true, [3577] = true, [3578] = true, [3580] = true, [3585] = true,
	[3590] = true, [3592] = true, [3593] = true, [3595] = true, [3597] = true, [3602] = true,
	[3603] = true, [3613] = true, [3616] = true, [3623] = true, [3628] = true, [3641] = true,
	[3651] = true, [3660] = true, [3664] = true, [3666] = true, [3669] = true, [3671] = true,
	[3682] = true, [3684] = true, [3685] = true, [3688] = true, [3703] = true, [3705] = true,
	[3708] = true, [3713] = true, [3714] = true, [3717] = true, [3718] = true, [3719] = true,
	[3731] = true, [3760] = true, [3792] = true, [3793] = true, [3874] = true, [3900] = true,
	[3912] = true, [3914] = true, [3917] = true, [3926] = true, [3970] = true, [3985] = true,
	[4023] = true, [4127] = true, [4128] = true, [4152] = true, [4169] = true, [4170] = true,
	[4171] = true, [4177] = true, [4179] = true, [4193] = true, [4200] = true, [4202] = true,
	[4204] = true, [4206] = true, [4208] = true, [4210] = true, [4230] = true, [4231] = true,
	[4240] = true, [4248] = true, [4250] = true, [4252] = true, [4269] = true, [4274] = true,
	[4306] = true, [4310] = true, [4312] = true, [4315] = true, [4337] = true, [4343] = true,
	[4360] = true, [4364] = true, [4372] = true, [4377] = true, [4379] = true, [4381] = true,
	[4385] = true, [4398] = true, [4399] = true, [4400] = true, [4402] = true, [4403] = true,
	[4412] = true, [4455] = true, [4456] = true, [4457] = true, [4496] = true, [4751] = true,
	[4757] = true, [4782] = true, [4801] = true, [4813] = true, [4861] = true, [4865] = true,
	[4953] = true, [4975] = true, [4977] = true, [4980] = true, [5131] = true, [5133] = true,
	[5137] = true, [5233] = true, [5247] = true, [5255] = true, [5256] = true, [5270] = true,
	[5277] = true, [5282] = true, [5284] = true, [5293] = true, [5297] = true, [5425] = true,
	[5427] = true, [5430] = true, [5438] = true, [5441] = true, [5443] = true, [5446] = true,
	[5447] = true, [5450] = true, [5458] = true, [5459] = true, [5477] = true, [5481] = true,
	[5493] = true, [5495] = true, [5496] = true, [5512] = true, [5513] = true, [5531] = true,
	[5549] = true, [5599] = true, [5609] = true, [5616] = true, [5624] = true, [5627] = true,
	[5631] = true, [5642] = true, [6161] = true, [6184] = true, [6223] = true, [6225] = true,
	[6245] = true, [6278] = true, [6280] = true, [6286] = true, [6306] = true, [6309] = true,
	[6313] = true, [6314] = true, [6318] = true, [6332] = true, [6414] = true, [6427] = true,
	[6916] = true, [7190] = true, [7194] = true, [7196] = true, [7200] = true, [7202] = true,
	[7203] = true, [7204] = true, [7205] = true, [7206] = true, [7210] = true, [7215] = true,
	[7216] = true, [7217] = true, [7218] = true, [7219] = true, [7220] = true, [7225] = true,
	[7228] = true, [7229] = true, [7230] = true, [7242] = true, [7259] = true, [7280] = true,
	[7281] = true, [7331] = true, [7343] = true, [7347] = true, [7361] = true, [7364] = true,
	[7379] = true, [7381] = true, [7392] = true, [7393] = true, [7395] = true, [7396] = true,
	[7397] = true, [7398] = true, [7399] = true, [7469] = true, [7485] = true, [7492] = true,
	[7503] = true, [7535] = true, [7562] = true, [7623] = true, [7625] = true, [7629] = true,
	[7632] = true, [7661] = true, [7662] = true, [7676] = true, [7679] = true, [7681] = true,
	[7719] = true, [7720] = true, [7721] = true, [7722] = true, [7730] = true, [7731] = true,
	[7732] = true, [7736] = true, [7744] = true, [7747] = true, [7751] = true, [7757] = true,
	[7758] = true, [7770] = true, [7782] = true, [7784] = true, [7787] = true, [7789] = true,
	[7790] = true, [7795] = true, [7797] = true, [7806] = true, [7809] = true, [7813] = true,
	[7835] = true, [7867] = true, [7868] = true, [7869] = true, [7894] = true, [7897] = true,
	[7898] = true, [7902] = true, [7905] = true, [7908] = true, [7913] = true, [7917] = true,
	[7919] = true, [7925] = true, [7933] = true, [7941] = true, [7942] = true, [7952] = true,
	[7953] = true, [7954] = true,
}

-------------------------------------
-- 更新设置面板界面
-------------------------------------
-- update scrollbar
_HM.UpdateListScroll = function()
	local handle, scroll = _HM.hList, _HM.hScroll
	local w, h = handle:GetSize()
	local wA, hA = handle:GetAllItemSize()
	local nStep = math.ceil((hA - h) / 10)
	scroll:SetStepCount(nStep)
	if nStep > 0 then
		scroll:Show()
		scroll:GetParent():Lookup("Btn_Up"):Show()
		scroll:GetParent():Lookup("Btn_Down"):Show()
	else
		scroll:Hide()
		scroll:GetParent():Lookup("Btn_Up"):Hide()
		scroll:GetParent():Lookup("Btn_Down"):Hide()
	end
end

-- updae detail content
_HM.UpdateDetail = function(i, data)
	local win = HM.UI.Fetch(_HM.frame, "Wnd_Detail")
	if win then win:Remove() end
	if not data then
		data = {}
		if HM_About then
			if not i then	-- default
				data.fn = {
					OnPanelActive = HM_About.OnPanelActive,
					GetAuthorInfo = HM_About.GetAuthorInfo,
				}
			elseif HM_About.OnTaboxCheck then	-- switch
				data.fn = {
					OnPanelActive = function(frame) HM_About.OnTaboxCheck(frame, i, _HM.tClass[i]) end,
					GetAuthorInfo = HM_About.GetAuthorInfo
				}
			end
		end
	end
	win = HM.UI.Append(_HM.frame, "WndActionWindow", "Wnd_Detail")
	win:Size(_HM.hContent:GetSize()):Pos(_HM.hContent:GetRelPos())
	if type(data.fn) == "table" then
		local szInfo = ""
		if data.fn.GetAuthorInfo then
			szInfo = "-- by " .. data.fn.GetAuthorInfo() .. " --"
		end
		_HM.hTotal:Lookup("Text_Author"):SetText(szInfo)
		if data.fn.OnPanelActive then
			data.fn.OnPanelActive(win:Raw())
			win.handle:FormatAllItemPos()
		end
		win.fnDestroy = data.fn.OnPanelDeactive
	end
end

-- create menu item
_HM.NewListItem = function(i, data, dwClass)
	local handle = _HM.hList
	local item = HM.UI.Append(handle, "BoxButton", "Button_" .. i)
	item:Icon(data.dwIcon):Text(data.szTitle):Click(function()
		_HM.UpdateDetail(dwClass, data)
	end, true, true)
	return item
end

-- update menu list
_HM.UpdateListInfo = function(nIndex)
	local nX, nY = 0, 14
	_HM.hList:Clear()
	_HM.hScroll:ScrollHome()
	_HM.UpdateDetail(nIndex)
	for k, v in ipairs(_HM.tItem[nIndex]) do
		local item = _HM.NewListItem(k, v, nIndex)
		item:Pos(nX, nY)
		nY = nY + 50
	end
	_HM.UpdateListScroll()
end

-- update tab list
_HM.UpdateTabBox = function(frame)
	local nX, nY, first = 25, 52, nil
	for k, v in ipairs(_HM.tClass) do
		if table.getn(_HM.tItem[k]) > 0 then
			local tab = frame:Lookup("TabBox_" .. k)
			if not tab then
				tab = HM.UI.Append(frame, "WndTabBox", "TabBox_" .. k, { group = "Nav" })
			else
				tab = HM.UI.Fetch(tab)
			end
			tab:Text(v):Pos(nX, nY):Click(function(bChecked)
				if bChecked then
					_HM.UpdateListInfo(k)
				end
			end):Check(false)
			if not first then
				first = tab
			end
			local nW, _ = tab:Size()
			nX = nX + math.ceil(nW) + 10
		end
	end
	if first then
		first:Check(true)
	end
end

-------------------------------------
-- 系统 HOOK
-------------------------------------
-- get player menu
_HM.GetPlayerMenu = function()
	local m0, n = {  szOption = _HM.szTitle }, 0
	table.insert(m0, { szOption = _L("Current version: v%s", HM.GetVersion()), fnDisable = function() return true end })
	table.insert(m0, { bDevide = true })
	-- append
	for _, v in ipairs(_HM.tMenu) do
		if type(v) == "function" then
			table.insert(m0, v())
		else
			table.insert(m0, v)
		end
		n = n + 1
	end
	-- OnPlayerMenu
	for _, v in ipairs(_HM.tItem) do
		local n2 = 0
		for _, vv in ipairs(v) do
			if vv.fn and vv.fn.OnPlayerMenu then
				local m1 = vv.fn.OnPlayerMenu()
				if n2 == 0 and n > 0 then
					n = 0
					table.insert(m0, { bDevide = true })
				end
				if m1.szOption then
					table.insert(m0, m1)
					n2 = n2 + 1
				else
					for _, m2 in ipairs(m1) do
						table.insert(m0, m2)
						n2 = n2 + 1
					end
				end
			end
		end
		if n == 0 then n = n2 end
	end
	-- debug
	if HM_About and HM_About.bDebug then
		local m1 = { szOption = "HM Debug Level [" .. _HM.nDebug .. "]", }
		for i = 1, 3 do
			table.insert(m1, {
				szOption = "Lv." .. i,
				bCheck = true, bMCheck = true, bChecked = i == _HM.nDebug,
				fnAction = function() _HM.nDebug = i end
			})
		end
		if n > 0 then
			table.insert(m0, { bDevide = true })
		end
		table.insert(m0, m1)
	end
	return { m0 }
end

-- hook player menu
_HM.HookPlayerMenu = function()
	Player_AppendAddonMenu({ _HM.GetPlayerMenu })
end

---------------------------------------------------------------------
-- 全局函数和变量（HM.xxx）
---------------------------------------------------------------------
HM = {
	szTitle = _HM.szTitle,						-- 插件集名称
	szBuildDate = _HM.szBuildDate,		-- 插件更新日期
	nBuildDate = 0,	-- 整型的更新日期（存入 CustomData）
}
RegisterCustomData("HM.nBuildDate")

-- (string, number) HM.GetVersion()		-- 取得字符串版本号和整型版本号
HM.GetVersion = function()
	local v = _HM.dwVersion
	local szVersion = string.format("%d.%d.%d", v/0x1000000,
		math.floor(v/0x10000)%0x100, math.floor(v/0x100)%0x100)
	if  v%0x100 ~= 0 then
		szVersion = szVersion .. "b" .. tostring(v%0x100)
	end
	return szVersion, v
end

-- (boolean) HM.IsPanelOpened()			-- 判断设置面板是否已打开
HM.IsPanelOpened = function()
	return _HM.frame and _HM.frame:IsVisible()
end

-- (void) HM.OpenPanel()							-- 打开设置面板
-- (void) HM.OpenPanel(string szTitle)		-- 打开名称为 szTitle 的插件或分组设置界面
HM.OpenPanel = function(szTitle)
	_HM.OpenPanel(szTitle ~= nil)
	if szTitle then
		local nClass, nItem = 0, 0
		for k, v in ipairs(_HM.tItem) do
			if _HM.tClass[k] == szTitle then
				nClass = k
				break
			end
			for kk, vv in ipairs(v) do
				if vv.szTitle == szTitle then
					nClass, nItem = k, kk
				end
			end
		end
		if nClass ~= 0 then
			HM.UI.Fetch(_HM.frame, "TabBox_" .. nClass):Check(true)
			if nItem ~= 0 then
				HM.UI.Fetch(_HM.hList, "Button_" .. nItem):Click()
			end
		end
	end
end

-- (void) HM.ClosePanel()				--  隐藏设置面板
-- (void) HM.ClosePanel(true)		-- 彻底关闭设置面板窗体
HM.ClosePanel = _HM.ClosePanel

-- (void) HM.TogglePanel()			-- 显示/隐藏设置面板
HM.TogglePanel= _HM.TogglePanel

-- 往插件集添加一个插件设置按纽及界面
-- (void) HM.RegisterPanel(string szTitle, number dwIcon, string szClass, table fn)
-- szTitle		-- 插件名称
--	dwIcon		-- 图标 ID
--	szClass		-- 分类名称，设为 nil 代表常用
--	fn {			-- 处理函数
--		OnPanelActive = (void) function(WndWindow frame),		-- 设置面板激活时调用，参数为设置画面的窗体对象
--		OnPanelDeactive = (void) function(WndWindow frame),	-- *可选* 设置面板被切出时调用，参数同上
--		OnConflictCheck = (void) function(),								-- *可选* 插件冲突检测函数（每次上线后调用一次）
--		OnPlayerMenu = (table) function(),									-- *可选* 返回附加的头像菜单
--		GetAuthorInfo = (string) function(),									-- *可选* 返回该插件的作者、版权信息
--	}
HM.RegisterPanel = function(szTitle, dwIcon, szClass, fn)
	-- find class
	local dwClass = nil
	if not szClass then
		dwClass = 1
	else
		for k, v in ipairs(_HM.tClass) do
			if v == szClass then
				dwClass = k
			end
		end
		if not dwClass then
			table.insert(_HM.tClass, szClass)
			dwClass = table.getn(_HM.tClass)
			_HM.tItem[dwClass] = {}
		end
	end
	-- check to update
	for _, v in ipairs(_HM.tItem[dwClass]) do
		if v.szTitle == szTitle then
			v.dwIcon, v.fn, dwClass = dwIcon, fn, nil
			break
		end
	end
	-- create new one
	if dwClass then
		table.insert(_HM.tItem[dwClass], { szTitle = szTitle, dwIcon = dwIcon, fn = fn })
	end
	if _HM.frame then
		_HM.UpdateTabBox(_HM.frame)
	end
	if fn and fn.OnConflictCheck then
		_HM.RegisterConflictCheck(fn.OnConflictCheck)
	end
end

-- (table) HM.GetPanelFunc(szTitle)		-- 获取 Hook 某个插件的初始化函数
HM.GetPanelFunc = function(szTitle)
	for k, v in ipairs(_HM.tItem) do
		for kk, vv in ipairs(v) do
			if vv.szTitle == szTitle then
				return vv.fn
			end
		end
	end
end

-- 登记需要临时设为目标的玩家（在非战斗状态会临时切换目标，以获取目标玩家的内功）
-- (void) HM.RegisterTempTarget(number dwID)
-- dwID		-- 需要关注的玩家 ID
HM.RegisterTempTarget = function(dwID)
	table.insert(_HM.tTempTarget, dwID)
end

-- 登记需要添加到头像菜单的项目
-- (void) HM.AppendPlayerMenu(table menu | func fnMenu)
-- menu 		-- 要添加的的菜单项或返回菜单项的函数
HM.AppendPlayerMenu = function(menu)
	table.insert(_HM.tMenu, menu)
end

-- 在聊天栏输出一段黄字（只有当前用户可见）
-- (void) HM.Sysmsg(string szMsg[, string szHead])
-- szMsg		-- 要输出的文字内容
--	szHead		-- 输出前缀，自动加上中括号，默认为：海鳗插件
HM.Sysmsg = function(szMsg, szHead, szType)
	szHead = szHead or _HM.szShort
	szType = szType or "MSG_SYS"
	OutputMessage(szType, "[" .. szHead .. "] " .. szMsg .. "\n")
end

-- 在聊天栏输出调试信息，和 HM.Sysmsg 类似，多了2个用于区分的符号标记
-- (void) HM.Debug(string szMsg[, string szHead])
-- (void) HM.Debug2(string szMsg[, string szHead])
-- (void) HM.Debug3(string szMsg[, string szHead])
HM.Debug = function(szMsg, szHead, nLevel)
	nLevel = nLevel or 1
	if HM_About and HM_About.bDebug and _HM.nDebug >= nLevel then
		if nLevel == 3 then szMsg = "### " .. szMsg
		elseif nLevel == 2 then szMsg = "=== " .. szMsg
		else szMsg = "-- " .. szMsg end
		HM.Sysmsg(szMsg, szHead)
	end
end
HM.Debug2 = function(szMsg, szHead) HM.Debug(szMsg, szHead, 2) end
HM.Debug3 = function(szMsg, szHead) HM.Debug(szMsg, szHead, 3) end

-- 在屏幕正中间弹出带一行文本和一个确定按纽的警示框
-- (void) HM.Alert(string szMsg, func fnAction, string szSure)
-- szMsg		-- 警示文字内容
-- fnAction	-- 按下确认按纽后触发的回调函数
-- szSure		-- 确认按纽的文字，默认：确定
HM.Alert = function(szMsg, fnAction, szSure)
	local nW, nH = Station.GetClientSize()
	local tMsg = {
		x = nW / 2, y = nH / 3, szMessage = szMsg, szName = "HM_Alert",
		{
			szOption = szSure or g_tStrings.STR_HOTKEY_SURE,
			fnAction = fnAction,
		},
	}
	MessageBox(tMsg)
end

-- 在屏幕中间弹出带两个按纽的确认框，并带有一行文本提示
-- (void) HM.Confirm(string szMsg, func fnAction, func fnCancel[, string szSure[, string szCancel]])
-- szMsg		-- 警示文字内容
-- fnAction	-- 按下确认按纽后触发的回调函数
-- fnCancel	-- 按下取消按纽后触发的回调函数
-- szSure		-- 确认按纽的文字，默认：确定
-- szCancel	-- 取消按纽的文字，默认：取消
HM.Confirm = function(szMsg, fnAction, fnCancel, szSure, szCancel)
	local nW, nH = Station.GetClientSize()
	local tMsg = {
		x = nW / 2, y = nH / 3, szMessage = szMsg, szName = "HM_Confirm",
		{
			szOption = szSure or g_tStrings.STR_HOTKEY_SURE,
			fnAction = fnAction,
		}, {
			szOption = szCancel or g_tStrings.STR_HOTKEY_CANCEL,
			fnAction = fnCancel,
		},
	}
	MessageBox(tMsg)
end

-- (void) HM.AddHotKey(string szName, string szTitle, func fnAction)	-- 增加系统快捷键
HM.AddHotKey = function(szName, szTitle, fnAction)
	if string.sub(1, 3) ~= "HM_" then
		szName = "HM_" .. szName
	end
	table.insert(_HM.tHotkey, { szName = szName, szTitle = szTitle, fnAction = fnAction })
end

-- (string) HM.GetHotKey(string szName, boolean bBracket, boolean bShort)		-- 取得快捷键名称
HM.GetHotKey = function(szName, bBracket, bShort)
	if string.sub(1, 3) ~= "HM_" then
		szName = "HM_" .. szName
	end
	local nKey, bShift, bCtrl, bAlt = Hotkey.Get(szName)
	local szKey = GetKeyShow(nKey, bShift, bCtrl, bAlt, bShort == true)
	if szKey ~= "" and bBracket then
		szKey = "(" .. szKey .. ")"
	end
	return szKey
end

-- (void) HM.SetHotKey()								-- 打开快捷键设置面板
-- (void) HM.SetHotKey(string szGroup)		-- 打开快捷键设置面板并定位到 szGroup 分组（不可用）
HM.SetHotKey = function(szGroup)
	HotkeyPanel_Open(szGroup or HM.szTitle)
end

-- 注册呼吸循环调用函数
-- (void) HM.BreatheCall(string szKey, func fnAction[, number nTime])
-- szKey		-- 名称，必须唯一，重复则覆盖
-- fnAction	-- 循环呼吸调用函数，设为 nil 则表示取消这个 key 下的呼吸处理函数
-- nTime		-- 调用间隔，单位：毫秒，默认为 62.5，即每秒调用 16次，其值自动被处理成 62.5 的整倍数
HM.BreatheCall = function(szKey, fnAction, nTime)
	local key = StringLowerW(szKey)
	if type(fnAction) == "function" then
		local nFrame = 1
		if nTime and nTime > 0 then
			nFrame = math.ceil(nTime / 62.5)
		end
		_HM.tBreatheCall[key] = { fnAction = fnAction, nNext = GetLogicFrameCount() + 1, nFrame = nFrame }
	else
		_HM.tBreatheCall[key] = nil
	end
end

-- 改变呼吸调用频率
-- (void) HM.BreatheCallDelay(string szKey, nTime)
-- nTime		-- 延迟时间，每 62.5 延迟一帧
HM.BreatheCallDelay = function(szKey, nTime)
	local t = _HM.tBreatheCall[StringLowerW(szKey)]
	if t then
		t.nFrame = math.ceil(nTime / 62.5)
		t.nNext = GetLogicFrameCount() + t.nFrame
	end
end

-- 延迟一次呼吸函数的调用频率
-- (void) HM.BreatheCallDelayOnce(string szKey, nTime)
-- nTime		-- 延迟时间，每 62.5 延迟一帧
HM.BreatheCallDelayOnce = function(szKey, nTime)
	local t = _HM.tBreatheCall[StringLowerW(szKey)]
	if t then
		t.nNext = GetLogicFrameCount() + math.ceil(nTime / 62.5)
	end
end

-- (void) HM.DelayCall(number nDelay, func fnAction)		-- 延迟调用
-- nTime		-- 延迟调用时间，单位：毫秒，实际调用延迟延迟是 62.5 的整倍数
-- fnAction	-- 调用函数
HM.DelayCall = function(nDelay, fnAction)
	local nTime = nDelay + GetTime()
	table.insert(_HM.tDelayCall, { nTime = nTime, fnAction = fnAction })
end

-- (void) HM.RemoteRequest(string szUrl, func fnAction)		-- 发起远程 HTTP 请求
-- szUrl		-- 请求的完整 URL（包含 http:// 或 https://）
-- fnAction 	-- 请求完成后的回调函数，回调原型：function(szTitle)
HM.RemoteRequest = function(szUrl, fnAction)
	local page = Station.Lookup("Normal/HM/Page_1")
	if page then
		_HM.tRequest[szUrl] = fnAction
		page:Navigate(szUrl)
	end
end

-- (KObject) HM.GetTarget()														-- 取得当前目标操作对象
-- (KObject) HM.GetTarget([number dwType, ]number dwID)	-- 根据 dwType 类型和 dwID 取得操作对象
HM.GetTarget = function(dwType, dwID)
	if not dwType then
		local me = GetClientPlayer()
		if me then
			dwType, dwID = me.GetTarget()
		else
			dwType, dwID = TARGET.NO_TARGET, 0
		end
	elseif not dwID then
		dwID, dwType = dwType, TARGET.NPC
		if IsPlayer(dwID) then
			dwType = TARGET.PLAYER
		end
	end
	if dwID <= 0 or dwType == TARGET.NO_TARGET then
		return nil, TARGET.NO_TARGET
	elseif dwType == TARGET.PLAYER then
		return GetPlayer(dwID), TARGET.PLAYER
	elseif dwType == TARGET.DOODAD then
		return GetDoodad(dwID), TARGET.DOODAD
	else
		return GetNpc(dwID), TARGET.NPC
	end
end

-- 根据 dwType 类型和 dwID 设置目标
-- (void) HM.SetTarget([number dwType, ]number dwID)
-- dwType	-- *可选* 目标类型
-- dwID		-- 目标 ID
HM.SetTarget = function(dwType, dwID)
	if not dwType or dwType <= 0 then
		dwType, dwID = TARGET.NO_TARGET, 0
	elseif not dwID then
		dwID, dwType = dwType, TARGET.NPC
		if IsPlayer(dwID) then
			dwType = TARGET.PLAYER
		end
	end
	SetTarget(dwType, dwID)
end

-- 切换临时目标，不改变目标面板
HM.SetInsTarget = function(...)
	TargetPanel_SetOpenState(true)
	HM.SetTarget(...)
	TargetPanel_SetOpenState(false)
end

-- 根据目标对像显示其名字
-- (string) HM.GetTargetName(userdata KNpc/KPlayer)
HM.GetTargetName = function(tar)
	local szName = tar.szName
	if tar.dwEmployer and tar.dwEmployer ~= 0 then
		local emp = GetPlayer(tar.dwEmployer)
		if not emp then
			szName =  g_tStrings.STR_SOME_BODY .. g_tStrings.STR_PET_SKILL_LOG .. tar.szName
		else
			szName = emp.szName .. g_tStrings.STR_PET_SKILL_LOG .. tar.szName
		end
	end
	return szName
end

-- 判断某个频道能否发言
-- (bool) HM.CanTalk(number nChannel)
HM.CanTalk = function(nChannel)
	for _, v in ipairs({"WHISPER", "TEAM", "RAID", "BATTLE_FIELD", "NEARBY", "TONG", "TONG_ALLIANCE" }) do
		if nChannel == PLAYER_TALK_CHANNEL[v] then
			return true
		end
	end
	return false
end

-- 切换聊天频道
-- (void) HM.SwitchChat(number nChannel)
HM.SwitchChat = function(nChannel)
	local szHeader = _HM.tTalkChannelHeader[nChannel]
	if szHeader then
		SwitchChatChannel(szHeader)
	elseif type(nChannel) == "string" then
		SwitchChatChannel("/w " .. nChannel .. " ")
	end
end


-- 发布聊天内容
-- (void) HM.Talk(string szTarget, string szText[, boolean bNoEmotion])
-- (void) HM.Talk([number nChannel, ] string szText[, boolean bNoEmotion])
-- szTarget			-- 密聊的目标角色名
-- szText				-- 聊天内容，（亦可为兼容 KPlayer.Talk 的 table）
-- nChannel			-- *可选* 聊天频道，PLAYER_TALK_CHANNLE.*，默认为近聊
-- bNoEmotion	-- *可选* 不解析聊天内容中的表情图片，默认为 false
-- bSaveDeny	-- *可选* 在聊天输入栏保留不可发言的频道内容，默认为 false
-- 特别注意：nChannel, szText 两者的参数顺序可以调换，战场/团队聊天频道智能切换
HM.Talk = function(nChannel, szText, bNoEmotion, bSaveDeny)
	local szTarget, me = "", GetClientPlayer()
	-- channel
	if not nChannel then
		nChannel = PLAYER_TALK_CHANNEL.NEARBY
	elseif type(nChannel) == "string" then
		if not szText then
			szText = nChannel
			nChannel = PLAYER_TALK_CHANNEL.NEARBY
		elseif type(szText) == "number" then
			szText, nChannel = nChannel, szText
		else
			szTarget = nChannel
			nChannel = PLAYER_TALK_CHANNEL.WHISPER
		end
	elseif nChannel == PLAYER_TALK_CHANNEL.RAID and me.GetScene().nType == MAP_TYPE.BATTLE_FIELD then
		nChannel = PLAYER_TALK_CHANNEL.BATTLE_FIELD
	end
	-- say body
	local tSay = nil
	if type(szText) == "table" then
		tSay = szText
	else
		local tar = HM.GetTarget(me.GetTarget())
		szText = string.gsub(szText, "%$zj", me.szName)
		if tar then
			szText = string.gsub(szText, "%$mb", tar.szName)
		end
		tSay = {{ type = "text", text = szText .. "\n"}}
	end
	if not bNoEmotion then
		tSay = _HM.ParseFaceIcon(tSay)
	end
	me.Talk(nChannel, szTarget, tSay)
	if bSaveDeny and not HM.CanTalk(nChannel) then
		local edit = Station.Lookup("Lowest2/EditBox/Edit_Input")
		edit:ClearText()
		for _, v in ipairs(tSay) do
			if v.type == "text" then
				edit:InsertText(v.text)
			else
				edit:InsertObj(v.text, v)
			end
		end
		-- change to this channel
		HM.SwitchChat(nChannel)
	end
end

-- 无法发言时保留文字在输入框
HM.Talk2 = function(nChannel, szText, bNoEmotion)
	HM.Talk(nChannel, szText, bNoEmotion, true)
end

-- 发布后台聊天通讯
-- (void) HM.BgTalk(szTarget, ...)
-- (void) HM.BgTalk(nChannel, ...)
-- szTarget			-- 密聊的目标角色名
-- nChannel			-- *可选* 聊天频道，PLAYER_TALK_CHANNLE.*，默认为近聊
-- ...						-- 若干个字符串参数组成，可原样被接收
HM.BgTalk = function(nChannel, ...)
	local tSay = { { type = "text", text = "BG_CHANNEL_MSG" } }
	local tArg = { ... }
	for _, v in ipairs(tArg) do
		if v == nil then
			break
		end
		table.insert(tSay, { type = "text", text = tostring(v) })
	end
	HM.Talk(nChannel, tSay, true)
end

-- 读取后台聊天数据，在 ON_BG_CHANNEL_MSG 事件处理函数中使用才有意义
-- (table) HM.BgHear([string szKey])
-- szKey			-- 通讯类型，也就是 HM.BgTalk 的第一数据参数，若不匹配则忽略
-- arg0: dwTalkerID, arg1: nChannel, arg2: bEcho, arg3: szName
HM.BgHear = function(szKey)
	local me = GetClientPlayer()
	local tSay = me.GetTalkData()
	if tSay and arg0 ~= me.dwID and tSay[1].text == "BG_CHANNEL_MSG" then
		local tData, nOff = {}, 2
		if szKey then
			if tSay[nOff].text ~= szKey then
				return nil
			end
			nOff = nOff + 1
		end
		for i = nOff, #tSay do
			table.insert(tData, tSay[i].text)
		end
		return tData
	end
end

-- (boolean) HM.IsDps([KPlayer tar])			-- 检查玩家是否为 DPS 内功，省略判断则判断自身
HM.IsDps = function(tar)
	tar = tar or GetClientPlayer()
	local mnt = tar.GetKungfuMount()
	return not mnt or (mnt.dwSkillID ~= 10080 and mnt.dwSkillID ~= 10028 and mnt.dwSkillID ~= 10176)
end

-- HM.GetMe
HM.Me = GetClientPlayer

-- (boolean) HM.IsParty(number dwID)		-- 根据玩家 ID 判断是否为队友
HM.IsParty = function(dwID)
	return GetClientPlayer().IsPlayerInMyParty(dwID)
end

-- (table) HM.GetAllPlayer([number nLimit])			-- 获取场景内的所有 玩家
-- nLimit	-- 个数上限，默认不限
HM.GetAllPlayer = function(nLimit)
	local aPlayer = {}
	for k, _ in pairs(_HM.aPlayer) do
		local p = GetPlayer(k)
		if not p then
			_HM.aPlayer[k] = nil
		elseif p.szName ~= "" then
			table.insert(aPlayer, p)
			if nLimit and #aPlayer == nLimit then
				break
			end
		end
	end
	return aPlayer
end

-- (table) HM.GetAllPlayerID()			-- 获取场景内的 NPC ID 列表
HM.GetAllPlayerID = function()
	return _HM.aPlayer
end

-- (table) HM.GetAllNpc([number nLimit])				-- 获取场景内的所有 NPC
-- nLimit	-- 个数上限，默认不限
HM.GetAllNpc = function(nLimit)
	local aNpc = {}
	for k, _ in pairs(_HM.aNpc) do
		local p = GetNpc(k)
		if not p then
			_HM.aNpc[k] = nil
		else
			table.insert(aNpc, p)
			if nLimit and #aNpc == nLimit then
				break
			end
		end
	end
	return aNpc
end

-- (table) HM.GetAllNpcID()			-- 获取场景内的 NPC ID 列表
HM.GetAllNpcID = function()
	return _HM.aNpc
end

-- (table) HM.GetAllDoodad([number nLimit])		-- 获取场景内的所有 DOODAD
-- nLimit -- 个数上限，默认不限
HM.GetAllDoodad = function(nLimit)
	local aDoodad = {}
	for k, _ in pairs(_HM.aDoodad) do
		local p = GetDoodad(k)
		if not p then
			_HM.aDoodad[k] = nil
		else
			table.insert(aDoodad, p)
			if nLimit and #aDoodad == nLimit then
				break
			end
		end
	end
	return aDoodad
end

-- (table) HM.GetAllDoodadID()			-- 获取场景内的 Doodad ID 列表
HM.GetAllDoodadID = function()
	return _HM.aDoodad
end

-- 计算目标与自身的距离
-- (number) HM.GetDistance(KObject tar)
-- (number) HM.GetDistance(number nX, number nY[, number nZ])
-- tar		-- 带有 nX，nY，nZ 三属性的 table 或 KPlayer，KNpc，KDoodad
-- nX		-- 世界坐标系下的目标点 X 值
-- nY		-- 世界坐标系下的目标点 Y 值
-- nZ		-- *可选* 世界坐标系下的目标点 Z 值
HM.GetDistance = function(nX, nY, nZ)
	local me = GetClientPlayer()
	if not nY and not nZ then
		local tar = nX
		nX, nY, nZ = tar.nX, tar.nY, tar.nZ
	elseif not nZ then
		return math.floor(((me.nX - nX) ^ 2 + (me.nY - nY) ^ 2) ^ 0.5)/64
	end
	return math.floor(((me.nX - nX) ^ 2 + (me.nY - nY) ^ 2 + (me.nZ/8 - nZ/8) ^ 2) ^ 0.5)/64
end

-- 根据目标所在位置、世界坐标点计算在屏幕上的相应位置并执行回调函数
-- (void) HM.ApplyScreenPoint(func fnAction, KObject tar[, string szKey])
-- (void) HM.ApplyScreenPoint(func fnAction, number nX, number nY, number nZ[, string szKey])
-- fnAction -- 取到坐标后调用，原型为 fnAction(nX, nY)，其中 nX, nY 为屏幕坐标，失败时参数为 nil
-- tar		-- 带有 nX，nY，nZ 三属性的 table 或 KPlayer，KNpc，KDoodad
-- nX		-- 世界坐标系下的目标点 X 值
-- nY		-- 世界坐标系下的目标点 Y 值
-- nZ		-- 世界坐标系下的目标点 Z 值
-- szKey	-- *可选* 调用标识（防止发送过多的请求，优化性能）
HM.ApplyScreenPoint = function(fnAction, nX, nY, nZ, szKey)
	if not nZ then
		local tar = nX
		szKey, nX, nY, nZ = nY, tar.nX, tar.nY, tar.nZ
	end
	if szKey and IsMultiThread() then
		if _HM.tApplyPointKey[szKey] then
			return
		end
		_HM.tApplyPointKey[szKey] = true
	else
		szKey = nil
	end
	PostThreadCall(_HM.ApplyPointCallback, { fnAction = fnAction, szKey = szKey },
		"Scene_GameWorldPositionToScreenPoint", nX, nY, nZ, false)
end

-- 计算目标头顶坐标点计算在屏幕上的相应位置并执行回调函数
-- (void) HM.ApplyTopPoint(func fnAction, KObject tar[, number nH[, string szKey]])
-- (void) HM.ApplyTopPoint(func fnAction, number dwID[, number nH[, string szKey]])
-- fnAction -- 取到坐标后调用，原型为 fnAction(nX, nY)，其中 nX, nY 为屏幕坐标，失败时参数为 nil
-- tar			-- 目标对象 KPlayer，KNpc，KDoodad
-- dwID		-- 目标 ID
-- nH			-- *可选* 高度，单位是：尺*64，默认对于 NPC/PLAYER 可智能计算头顶
-- szKey		-- *可选* 调用标识（防止发送过多的请求，优化性能）
HM.ApplyTopPoint = function(fnAction, tar, nH, szKey)
	if type(tar) == "number" then
		tar = HM.GetTarget(tar)
	end
	if not tar then
		return fnAction()
	end
	if type(nH) == "string" then
		szKey, nH = nH, nil
	end
	if szKey and IsMultiThread() then
		if _HM.tApplyPointKey[szKey] then
			return
		end
		_HM.tApplyPointKey[szKey] = true
	else
		szKey = nil
	end
	if not nH then
		PostThreadCall(_HM.ApplyPointCallback, { fnAction = fnAction, szKey = szKey },
			"Scene_GetCharacterTopScreenPos", tar.dwID)
	else
		if nH < 64 then
			nH = nH * 64
		end
		PostThreadCall(_HM.ApplyPointCallback, { fnAction = fnAction, szKey = szKey },
			"Scene_GameWorldPositionToScreenPoint", tar.nX, tar.nY, tar.nZ + nH, false)
	end
end

-- 追加小地图标记
-- (void) HM.UpdateMiniFlag(number dwType, KObject tar, number nF1[, number nF2])
-- dwType	-- 类型，8 - 红名，5 - Doodad，7 - 功能 NPC，2 - 提示点，1 - 队友，4 - 任务 NPC
-- tar			-- 目标对象 KPlayer，KNpc，KDoodad
-- nF1			-- 图标帧次
-- nF2			-- 箭头帧次，默认 48 就行
HM.UpdateMiniFlag = function(dwType, tar, nF1, nF2)
	local nX, nZ = Scene_PlaneGameWorldPosToScene(tar.nX, tar.nY)
	local m = Station.Lookup("Normal/Minimap/Wnd_Minimap/Minimap_Map")
	if m then
		m:UpdataArrowPoint(dwType, tar.dwID, nF1, nF2 or 48, nX, nZ, 16)
	end
end

-- (table) HM.Split(string szFull, string szSep)		-- 根据 szSep 分割字符串 szFull，不支持表达式
HM.Split = function(szFull, szSep)
	local nOff, tResult = 1, {}
	while true do
		local nEnd = StringFindW(szFull, szSep, nOff)
		if not nEnd then
			table.insert(tResult, string.sub(szFull, nOff, string.len(szFull)))
			break
		else
			table.insert(tResult, string.sub(szFull, nOff, nEnd - 1))
			nOff = nEnd + string.len(szSep)
		end
	end
	return tResult
end

-- (string) HM.Trim(string szText)				-- 清除字符串首尾的空白字符
HM.Trim = function(szText)
	if not szText or szText == "" then
		return ""
	end
	return (string.gsub(szText, "^%s*(.-)%s*$", "%1"))
end

-- (string) HM.UrlEncode(string szText)		-- 转换为 URL 编码
HM.UrlEncode = function(szText)
	local str = szText:gsub("([^0-9a-zA-Z ])", function (c) return string.format ("%%%02X", string.byte(c)) end)
	str = str:gsub(" ", "+")
	return str
end

-- 根据技能 ID 及等级获取技能的名称及图标 ID（内置缓存处理）
-- (string, number) HM.GetSkillName(number dwSkillID[, number dwLevel])
HM.GetSkillName = function(dwSkillID, dwLevel)
	if not _HM.tSkillCache[dwSkillID] then
		local tLine = Table_GetSkill(dwSkillID, dwLevel)
		if tLine and tLine.dwSkillID > 0 and tLine.bShow
			and (StringFindW(tLine.szDesc, "_") == nil  or StringFindW(tLine.szDesc, "<") ~= nil)
		then
			_HM.tSkillCache[dwSkillID] = { tLine.szName, tLine.dwIconID }
		else
			local szName = "SKILL#" .. dwSkillID
			if dwLevel then
				szName = szName .. ":" .. dwLevel
			end
			_HM.tSkillCache[dwSkillID] = { szName, 13 }
		end
	end
	return unpack(_HM.tSkillCache[dwSkillID])
end

-- 根据Buff ID 及等级获取 BUFF 的名称及图标 ID（内置缓存处理）
-- (string, number) HM.GetBuffName(number dwBuffID[, number dwLevel])
HM.GetBuffName = function(dwBuffID, dwLevel)
	local xKey = dwBuffID
	if dwBuffID == 4937 and dwLevel ~= nil then
		xKey = dwBuffID .. "_" .. dwLevel
	end
	if not _HM.tBuffCache[xKey] then
		local tLine = Table_GetBuff(dwBuffID, dwLevel or 1)
		if tLine then
			_HM.tBuffCache[xKey] = { tLine.szName, tLine.dwIconID }
		else
			local szName = "BUFF#" .. dwBuffID
			if dwLevel then
				szName = szName .. ":" .. dwLevel
			end
			_HM.tBuffCache[xKey] = { szName, -1 }
		end
	end
	return unpack(_HM.tBuffCache[xKey])
end

-- 注册事件，和系统的区别在于可以指定一个 KEY 防止多次加载
-- (void) HM.RegisterEvent(string szEvent, func fnAction[, string szKey])
-- szEvent		-- 事件，可在后面加一个点并紧跟一个标识字符串用于防止重复或取消绑定，如 LOADING_END.xxx
-- fnAction		-- 事件处理函数，arg0 ~ arg9，传入 nil 相当于取消该事件
--特别注意：当 fnAction 为 nil 并且 szKey 也为 nil 时会取消所有通过本函数注册的事件处理器
HM.RegisterEvent = function(szEvent, fnAction)
	local szKey = nil
	local nPos = StringFindW(szEvent, ".")
	if nPos then
		szKey = string.sub(szEvent, nPos + 1)
		szEvent = string.sub(szEvent, 1, nPos - 1)
	end
	if not _HM.tEvent[szEvent] then
		_HM.tEvent[szEvent] = {}
		RegisterEvent(szEvent, function() _HM.EventHandler(szEvent) end)
	end
	local tEvent = _HM.tEvent[szEvent]
	if fnAction then
		if not szKey then
			table.insert(tEvent, fnAction)
		else
			tEvent[szKey] = fnAction
		end
	else
		if not szKey then
			_HM.tEvent[szEvent] = {}
		else
			tEvent[szKey] = nil
		end
	end
end

-- 取消事件处理函数
-- (void) HM.UnRegisterEvent(string szEvent)
HM.UnRegisterEvent = function(szEvent)
	HM.RegisterEvent(szEvent, nil)
end

-- 注册用户定义数据，支持全局变量数组遍历
-- (void) HM.RegisterCustomData(string szVarPath)
HM.RegisterCustomData = function(szVarPath)
	if _G and type(_G[szVarPath]) == "table" then
		for k, _ in pairs(_G[szVarPath]) do
			RegisterCustomData(szVarPath .. "." .. k)
		end
	else
		RegisterCustomData(szVarPath)
	end
end

-- Role Custom Data 加载后判断比较 nUpdateDate 然后调用 fnAction
-- (void) HM.RegisterCustomUpdater(func fnAction, number nUpdateDate)
HM.RegisterCustomUpdater = function(fnAction, nUpdateDate)
	table.insert(_HM.tCustomUpdateCall, { nDate = nUpdateDate, fnAction = fnAction })
end

-- 判断当前用户是否可用某个技能
-- (bool) HM.CanUseSkill(number dwSkillID[, dwLevel])
HM.CanUseSkill = function(dwSkillID, dwLevel)
	local me, box = GetClientPlayer(), _HM.hBox
	if me and box then
		if not dwLevel then
			if dwSkillID ~= 9007 then
				dwLevel = me.GetSkillLevel(dwSkillID)
			else
				dwLevel = 1
			end
		end
		if dwLevel > 0 then
			box:EnableObject(false)
			box:SetObjectCoolDown(1)
			box:SetObject(UI_OBJECT_SKILL, dwSkillID, dwLevel)
			UpdataSkillCDProgress(me, box)
			return box:IsObjectEnable() and not box:IsObjectCoolDown()
		end
	end
	return false
end

-- 根据技能 ID 获取引导帧数，非引导技能返回 nil
-- (number) HM.GetChannelSkillFrame(number dwSkillID)
HM.GetChannelSkillFrame = function(dwSkillID)
	return _HM.tChannelSkill[dwSkillID]
end

-- 根据技能 ID 判断当前技能是否可打断
-- (bool) HM.CanBrokenSkill(number dwSkillID)
HM.CanBrokenSkill = function(dwSkillID)
	return not _HM.tNonBrokenSkill[dwSkillID]
end

-- 根据名称获取弹出菜单数据，可调返回值中的 fnAction 执行操作
-- (table) HM.GetPopupMenuItem(string szOption)
HM.GetPopupMenuItem = function(szOption)
    local frame = Station.Lookup("Topmost1/PopupMenuPanel")
    if not frame or not frame:IsVisible() then
        return
    end
    local hItemGroup = frame:Lookup("", ""):Lookup(0):Lookup("Handle_Item_Group")
    for i = 0, hItemGroup:GetItemCount() - 1, 1 do
        local hItem = hItemGroup:Lookup(i)
        if hItem.tData then
            local t = _HM.FetchMenuItem(hItem.tData, szOption)
            if t then
                return t
            end
        end
    end
end

-- 自动执行弹出的确认框
-- (void) HM.DoMessageBox(string szName, [number i ])
-- szName		-- 确认框的名字
-- i 					-- 要执行的选项编号，从 1 开始，默认为 1
HM.DoMessageBox = function(szName, i)
	local frame = Station.Lookup("Topmost2/MB_" .. szName) or Station.Lookup("Topmost/MB_" .. szName)
	if frame then
		i = i or 1
		local btn = frame:Lookup("Wnd_All/Btn_Option" .. i)
		if btn and btn:IsEnabled() then
			if btn.fnAction then
				btn.fnAction(i)
			elseif frame.fnAction then
				frame.fnAction(i)
			end
			CloseMessageBox(szName)
		end
	end
end

-- 获取背包空位总数
-- (number) HM.GetFreeBagBoxNum()
HM.GetFreeBagBoxNum = function()
	local me, nFree = GetClientPlayer(), 0
	for i = 1, BigBagPanel_nCount do
		nFree = nFree + me.GetBoxFreeRoomSize(i)
	end
	return nFree
end

-- 获取第一个背包空位
-- (number, number) HM.GetFreeBagBox()
HM.GetFreeBagBox = function()
	local me = GetClientPlayer()
	for i = 1, BigBagPanel_nCount do
		if me.GetBoxFreeRoomSize(i) > 0 then
			for j = 0, me.GetBoxSize(i) - 1 do
				if not me.GetItem(i, j) then
					return i, j
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- 可重复利用的简易 Handle 元件缓存池
---------------------------------------------------------------------
_HM.HandlePool= class()

-- construct
function _HM.HandlePool:ctor(handle, xml)
	self.handle, self.xml = handle, xml
	handle.nFreeCount = 0
	handle:Clear()
end

-- clear
function _HM.HandlePool:Clear()
	self.handle:Clear()
	self.handle.nFreeCount = 0
end

-- new item
function _HM.HandlePool:New()
	local handle = self.handle
	local nCount = handle:GetItemCount()
	if handle.nFreeCount > 0 then
		for i = nCount - 1, 0, -1 do
			local item = handle:Lookup(i)
			if item.bFree then
				item.bFree = false
				handle.nFreeCount = handle.nFreeCount - 1
				return item
			end
		end
		handle.nFreeCount = 0
	else
		handle:AppendItemFromString(self.xml)
		local item = handle:Lookup(nCount)
		item.bFree = false
		return item
	end
end

-- remove item
function _HM.HandlePool:Remove(item)
	if item:IsValid() then
		self.handle:RemoveItem(item)
	end
end

-- free item
function _HM.HandlePool:Free(item)
	if item:IsValid() then
		self.handle.nFreeCount = self.handle.nFreeCount + 1
		item.bFree = true
		item:Hide()
	end
end

-- public api, create pool
-- (class) HM.HandlePool(userdata handle, string szXml)
HM.HandlePool = _HM.HandlePool.new

---------------------------------------------------------------------
-- 本地的 UI 组件对象
---------------------------------------------------------------------
_HM.UI = {}

-------------------------------------
-- Base object class
-------------------------------------
_HM.UI.Base = class()

-- (userdata) Instance:Raw()		-- 获取原始窗体/组件对象
function _HM.UI.Base:Raw()
	if self.type == "Label" then
		return self.txt
	end
	return self.wnd or self.edit or self.self
end

-- (void) Instance:Remove()		-- 删除组件
function _HM.UI.Base:Remove()
	if self.fnDestroy then
		local wnd = self.wnd or self.self
		self.fnDestroy(wnd)
	end
	local hP = self.self:GetParent()
	if hP.___uis then
		local szName = self.self:GetName()
		hP.___uis[szName] = nil
	end
	if self.type == "WndFrame" then
		Wnd.CloseWindow(self.self)
	elseif string.sub(self.type, 1, 3) == "Wnd" then
		self.self:Destroy()
	else
		hP:RemoveItem(self.self:GetIndex())
	end
end

-- (string) Instance:Name()					-- 取得名称
-- (self) Instance:Name(szName)			-- 设置名称为 szName 并返回自身以支持串接调用
function _HM.UI.Base:Name(szName)
	if not szName then
		return self.self:GetName()
	end
	self.self:SetName(szName)
	return self
end

-- (self) Instance:Toggle([boolean bShow])			-- 显示/隐藏
function _HM.UI.Base:Toggle(bShow)
	if bShow == false or (not bShow and self.self:IsVisible()) then
		self.self:Hide()
	else
		self.self:Show()
		if self.type == "WndFrame" then
			self.self:BringToTop()
		end
	end
	return self.self
end

-- (number, number) Instance:Pos()					-- 取得位置坐标
-- (self) Instance:Pos(number nX, number nY)	-- 设置位置坐标
function _HM.UI.Base:Pos(nX, nY)
	if not nX then
		return self.self:GetRelPos()
	end
	self.self:SetRelPos(nX, nY)
	if self.type == "WndFrame" then
		self.self:CorrectPos()
	elseif string.sub(self.type, 1, 3) ~= "Wnd" then
		self.self:GetParent():FormatAllItemPos()
	end
	return self
end

-- (number, number) Instance:Pos_()			-- 取得右下角的坐标
function _HM.UI.Base:Pos_()
	local nX, nY = self:Pos()
	local nW, nH = self:Size()
	return nX + nW, nY + nH
end

-- (number, number) Instance:CPos_()			-- 取得最后一个子元素右下角坐标
-- 特别注意：仅对通过 :Append() 追加的元素有效，以便用于动态定位
function _HM.UI.Base:CPos_()
	local hP = self.wnd or self.self
	if not hP.___last and string.sub(hP:GetType(), 1, 3) == "Wnd" then
		hP = hP:Lookup("", "")
	end
	if hP.___last then
		local ui = HM.UI.Fetch(hP, hP.___last)
		if ui then
			return ui:Pos_()
		end
	end
	return 0, 0
end

-- (class) Instance:Append(string szType, ...)	-- 添加 UI 子组件
-- NOTICE：only for Handle，WndXXX
function _HM.UI.Base:Append(szType, ...)
	local hP = self.wnd or self.self
	if string.sub(hP:GetType(), 1, 3) == "Wnd" and string.sub(szType, 1, 3) ~= "Wnd" then
		hP.___last = nil
		hP = hP:Lookup("", "")
	end
	return HM.UI.Append(hP, szType, ...)
end

-- (class) Instance:Fetch(string szName)	-- 根据名称获取 UI 子组件
function _HM.UI.Base:Fetch(szName)
	local hP = self.wnd or self.self
	local ui = HM.UI.Fetch(hP, szName)
	if not ui and self.handle then
		ui = HM.UI.Fetch(self.handle, szName)
	end
	return ui
end

-- (number, number) Instance:Align()
-- (self) Instance:Align(number nHAlign, number nVAlign)
function _HM.UI.Base:Align(nHAlign, nVAlign)
	local txt = self.edit or self.txt
	if txt then
		if not nHAlign and not nVAlign then
			return txt:GetHAlign(), txt:GetVAlign()
		else
			if nHAlign then
				txt:SetHAlign(nHAlign)
			end
			if nVAlign then
				txt:SetVAlign(nVAlign)
			end
		end
	end
	return self
end

-- (number) Instance:Font()
-- (self) Instance:Font(number nFont)
function _HM.UI.Base:Font(nFont)
	local txt = self.edit or self.txt
	if txt then
		if not nFont then
			return txt:GetFontScheme()
		end
		txt:SetFontScheme(nFont)
	end
	return self
end

-- (number, number, number) Instance:Color()
-- (self) Instance:Color(number nRed, number nGreen, number nBlue)
function _HM.UI.Base:Color(nRed, nGreen, nBlue)
	if self.type == "Shadow" then
		if not nRed then
			return self.self:GetColorRGB()
		end
		self.self:SetColorRGB(nRed, nGreen, nBlue)
	else
		local txt = self.edit or self.txt
		if txt then
			if not nRed then
				return txt:GetFontColor()
			end
			txt:SetFontColor(nRed, nGreen, nBlue)
		end
	end
	return self
end

-- (number) Instance:Alpha()
-- (self) Instance:Alpha(number nAlpha)
function _HM.UI.Base:Alpha(nAlpha)
	local txt = self.edit or self.txt or self.self
	if txt then
		if not nAlpha then
			return txt:GetAlpha()
		end
		txt:SetAlpha(nAlpha)
	end
	return self
end

-------------------------------------
-- Dialog frame
-------------------------------------
_HM.UI.Frm = class(_HM.UI.Base)

-- constructor
function _HM.UI.Frm:ctor(szName, bEmpty)
	local frm, szIniFile = nil, "interface\\HM\\ui\\WndFrame.ini"
	if bEmpty then
		szIniFile = "interface\\HM\\ui\\WndFrameEmpty.ini"
	end
	if type(szName) == "string" then
		frm = Station.Lookup("Normal/" .. szName)
		if frm then
			Wnd.CloseWindow(frm)
		end
		frm = Wnd.OpenWindow(szIniFile, szName)
	else
		frm = Wnd.OpenWindow(szIniFile)
	end
	frm:Show()
	if not bEmpty then
		frm:SetPoint("CENTER", 0, 0, "CENTER", 0, 0)
		frm:Lookup("Btn_Close").OnLButtonClick = function()
			if frm.bClose then
				Wnd.CloseWindow(frm)
			else
				frm:Hide()
			end
		end
		self.wnd = frm:Lookup("Window_Main")
	end
	self.self, self.type = frm, "WndFrame"
end

-- (number, number) Instance:Size()						-- 取得窗体宽和高
-- (self) Instance:Size(number nW, number nH)	-- 设置窗体的宽和高
-- 特别注意：窗体最小高度为 200，宽度自动按接近取  234/380/770 中的一个
function _HM.UI.Frm:Size(nW, nH)
	local frm = self.self
	if not nW then
		return frm:GetSize()
	end
	local hnd = frm:Lookup("", "")
	-- empty frame
	if not self.wnd then
		frm:SetSize(nW, nH)
		hnd:SetSize(nW, nH)
		return self
	end
	-- fix size
	if nW > 400 then
		nW = 770
		hnd:Lookup("Image_CBg1"):SetSize(385, 70)
		hnd:Lookup("Image_CBg2"):SetSize(384, 70)
		hnd:Lookup("Image_CBg1"):SetFrame(2)
		hnd:Lookup("Image_CBg2"):SetFrame(2)
	elseif nW > 250 then
		nW = 380
		hnd:Lookup("Image_CBg1"):SetSize(190, 70)
		hnd:Lookup("Image_CBg2"):SetSize(189, 70)
		hnd:Lookup("Image_CBg1"):SetFrame(1)
		hnd:Lookup("Image_CBg2"):SetFrame(1)
	else
		nW = 234
		hnd:Lookup("Image_CBg1"):SetSize(117, 70)
		hnd:Lookup("Image_CBg2"):SetSize(117, 70)
		hnd:Lookup("Image_CBg1"):SetFrame(0)
		hnd:Lookup("Image_CBg2"):SetFrame(0)
	end
	if nH < 200 then nH = 200 end
	-- set size
	frm:SetSize(nW, nH)
	frm:SetDragArea(0, 0, nW, 70)
	hnd:SetSize(nW, nH)
	hnd:Lookup("Image_CBg3"):SetSize(8, nH - 160)
	hnd:Lookup("Image_CBg4"):SetSize(nW - 16, nH - 160)
	hnd:Lookup("Image_CBg5"):SetSize(8, nH - 160)
	hnd:Lookup("Image_CBg7"):SetSize(nW - 132, 85)
	hnd:Lookup("Text_Title"):SetSize(nW - 90, 30)
	hnd:FormatAllItemPos()
	frm:Lookup("Btn_Close"):SetRelPos(nW - 35, 15)
	self.wnd:SetSize(nW - 90, nH - 90)
	self.wnd:Lookup("", ""):SetSize(nW - 90, nH - 90)
	-- reset position
	local an = GetFrameAnchor(frm)
	frm:SetPoint(an.s, 0, 0, an.r, an.x, an.y)
	return self
end

-- (string) Instance:Title()					-- 取得窗体标题
-- (self) Instance:Title(string szTitle)	-- 设置窗体标题
function _HM.UI.Frm:Title(szTitle)
	local ttl = self.self:Lookup("", "Text_Title")
	if not szTitle then
		return ttl:GetText()
	end
	ttl:SetText(szTitle)
	return self
end

-- (boolean) Instance:Drag()						-- 判断窗体是否可拖移
-- (self) Instance:Drag(boolean bEnable)	-- 设置窗体是否可拖移
function _HM.UI.Frm:Drag(bEnable)
	local frm = self.self
	if bEnable == nil then
		return frm:IsDragable()
	end
	frm:EnableDrag(bEnable == true)
	return self
end

-- (string) Instance:Relation()
-- (self) Instance:Relation(string szName)	-- Normal/Lowest ...
function _HM.UI.Frm:Relation(szName)
	local frm = self.self
	if not szName then
		return frm:GetParent():GetName()
	end
	frm:ChangeRelation(szName)
	return self
end

-- (userdata) Instance:Lookup(...)
function _HM.UI.Frm:Lookup(...)
	local wnd = self.wnd or self.self
	return self.wnd:Lookup(...)
end

-------------------------------------
-- Window Component
-------------------------------------
_HM.UI.Wnd = class(_HM.UI.Base)

-- constructor
function _HM.UI.Wnd:ctor(pFrame, szType, szName)
	local wnd = nil
	if not szType and not szName then
		-- convert from raw object
		wnd, szType = pFrame, pFrame:GetType()
	else
		-- append from ini file
		local szFile = "interface\\HM\\ui\\" .. szType .. ".ini"
		local frame = Wnd.OpenWindow(szFile, "HM_Virtual")
		if not frame then
			return HM.Sysmsg(_L("Unable to open ini file [%s]", szFile))
		end
		wnd = frame:Lookup(szType)
		if not wnd then
			HM.Sysmsg(_L("Can not find wnd component [%s]", szType))
		else
			wnd:SetName(szName)
			wnd:ChangeRelation(pFrame, true, true)
		end
		Wnd.CloseWindow(frame)
	end
	if wnd then
		self.type = szType
		self.edit = wnd:Lookup("Edit_Default")
		self.handle = wnd:Lookup("", "")
		self.self = wnd
		if self.handle then
			self.txt = self.handle:Lookup("Text_Default")
		end
		if szType == "WndTrackBar" then
			local scroll = wnd:Lookup("Scroll_Track")
			scroll.nMin, scroll.nMax, scroll.szText = 0, scroll:GetStepCount(), self.txt:GetText()
			scroll.nVal = scroll.nMin
			self.txt:SetText(scroll.nVal .. scroll.szText)
			scroll.OnScrollBarPosChanged = function()
				this.nVal = this.nMin + math.ceil((this:GetScrollPos() / this:GetStepCount()) * (this.nMax - this.nMin))
				if this.OnScrollBarPosChanged_ then
					this.OnScrollBarPosChanged_(this.nVal)
				end
				self.txt:SetText(this.nVal .. this.szText)
			end
		end
	end
end

-- (number, number) Instance:Size()
-- (self) Instance:Size(number nW, number nH)
function _HM.UI.Wnd:Size(nW, nH)
	local wnd = self.self
	if not nW then
		local nW, nH = wnd:GetSize()
		if self.type == "WndRadioBox" or self.type == "WndCheckBox" or self.type == "WndTrackBar" then
			local xW, _ = self.txt:GetTextExtent()
			nW = nW + xW + 5
		end
		return nW, nH
	end
	if self.edit then
		wnd:SetSize(nW + 2, nH)
		self.handle:SetSize(nW + 2, nH)
		self.handle:Lookup("Image_Default"):SetSize(nW + 2, nH)
		self.edit:SetSize(nW, nH)
	else
		wnd:SetSize(nW, nH)
		if self.handle then
			self.handle:SetSize(nW, nH)
			if self.type == "WndButton" or self.type == "WndTabBox" then
				self.txt:SetSize(nW, nH)
			elseif self.type == "WndComboBox" then
				self.handle:Lookup("Image_ComboBoxBg"):SetSize(nW, nH)
				local btn = wnd:Lookup("Btn_ComboBox")
				local hnd = btn:Lookup("", "")
				local bW, bH = btn:GetSize()
				btn:SetRelPos(nW - bW - 5, math.ceil((nH - bH)/2))
				hnd:SetAbsPos(self.handle:GetAbsPos())
				hnd:SetSize(nW, nH)
				self.txt:SetSize(nW - math.ceil(bW/2), nH)
			elseif self.type == "WndCheckBox" then
				local _, xH = self.txt:GetTextExtent()
				self.txt:SetRelPos(nW - 20, math.floor((nH - xH)/2))
				self.handle:FormatAllItemPos()
			elseif self.type == "WndRadioBox" then
				local _, xH = self.txt:GetTextExtent()
				self.txt:SetRelPos(nW + 5, math.floor((nH - xH)/2))
				self.handle:FormatAllItemPos()
			elseif self.type == "WndTrackBar" then
				wnd:Lookup("Scroll_Track"):SetSize(nW, nH - 13)
				wnd:Lookup("Scroll_Track/Btn_Track"):SetSize(math.ceil(nW/5), nH - 13)
				self.handle:Lookup("Image_BG"):SetSize(nW, nH - 15)
				self.handle:Lookup("Text_Default"):SetRelPos(nW + 5, math.ceil((nH - 25)/2))
				self.handle:FormatAllItemPos()
			end
		end
	end
	return self
end

-- (boolean) Instance:Enable()
-- (self) Instance:Enable(boolean bEnable)
function _HM.UI.Wnd:Enable(bEnable)
	local wnd = self.edit or self.self
	local txt = self.edit or self.txt
	if bEnable == nil then
		if self.type == "WndButton" then
			return wnd:IsEnabled()
		end
		return self.enable ~= false
	end
	if bEnable then
		wnd:Enable(1)
		if txt and self.font then
			txt:SetFontScheme(self.font)
		end
		self.enable = true
	else
		wnd:Enable(0)
		if txt and self.enable ~= false then
			self.font = txt:GetFontScheme()
			txt:SetFontScheme(161)
		end
		self.enable = false
	end
	return self
end

-- (self) Instance:AutoSize([number hPad[, number vPad]])
function _HM.UI.Wnd:AutoSize(hPad, vPad)
	local wnd = self.self
	if self.type == "WndTabBox" or self.type == "WndButton" then
		local _, nH = wnd:GetSize()
		local nW, _ = self.txt:GetTextExtent()
		local nEx = self.txt:GetTextPosExtent()
		if hPad then
			nW = nW + hPad + hPad
		end
		if vPad then
			nH = nH + vPad + vPad
		end
		self:Size(nW + nEx + 16, nH)
	elseif self.type == "WndComboBox" then
		local bW, _ = wnd:Lookup("Btn_ComboBox"):GetSize()
		local nW, nH = self.txt:GetTextExtent()
		local nEx = self.txt:GetTextPosExtent()
		if hPad then
			nW = nW + hPad + hPad
		end
		if vPad then
			nH = nH + vPad + vPad
		end
		self:Size(nW + bW + 20, nH + 6)
	end
	return self
end

-- (boolean) Instance:Check()
-- (self) Instance:Check(boolean bCheck)
-- NOTICE：only for WndCheckBox
function _HM.UI.Wnd:Check(bCheck)
	local wnd = self.self
	if wnd:GetType() == "WndCheckBox" then
		if bCheck == nil then
			return wnd:IsCheckBoxChecked()
		end
		wnd:Check(bCheck == true)
	end
	return self
end

-- (string) Instance:Group()
-- (self) Instance:Group(string szGroup)
-- NOTICE：only for WndCheckBox
function _HM.UI.Wnd:Group(szGroup)
	local wnd = self.self
	if wnd:GetType() == "WndCheckBox" then
		if not szGroup then
			return wnd.group
		end
		wnd.group = szGroup
	end
	return self
end

-- (string) Instance:Url()
-- (self) Instance:Url(string szUrl)
-- NOTICE：only for WndWebPage
function _HM.UI.Wnd:Url(szUrl)
	local wnd = self.self
	if self.type == "WndWebPage" then
		if not szUrl then
			return wnd:GetLocationURL()
		end
		wnd:Navigate(szUrl)
	end
	return self
end

-- (number, number, number) Instance:Range()
-- (self) Instance:Range(number nMin, number nMax[, number nStep])
-- NOTICE：only for WndTrackBar
function _HM.UI.Wnd:Range(nMin, nMax, nStep)
	if self.type == "WndTrackBar" then
		local scroll = self.self:Lookup("Scroll_Track")
		if not nMin and not nMax then
			return scroll.nMin, scroll.nMax, scroll:GetStepCount()
		end
		if nMin then scroll.nMin = nMin end
		if nMax then scroll.nMax = nMax end
		if nStep then scroll:SetStepCount(nStep) end
		self:Value(scroll.nVal)
	end
	return self
end

-- (number) Instance:Value()
-- (self) Instance:Value(number nVal)
-- NOTICE：only for WndTrackBar
function _HM.UI.Wnd:Value(nVal)
	if self.type == "WndTrackBar" then
		local scroll = self.self:Lookup("Scroll_Track")
		if not nVal then
			return scroll.nVal
		end
		scroll.nVal = math.min(math.max(nVal, scroll.nMin), scroll.nMax)
		scroll:SetScrollPos(math.ceil((scroll.nVal - scroll.nMin) / (scroll.nMax - scroll.nMin) * scroll:GetStepCount()))
		self.txt:SetText(scroll.nVal .. scroll.szText)
	end
	return self
end

-- (string) Instance:Text()
-- (self) Instance:Text(string szText[, boolean bDummy])
-- bDummy		-- 设为 true 不触发输入框的 onChange 事件
function _HM.UI.Wnd:Text(szText, bDummy)
	local txt = self.edit or self.txt
	if txt then
		if not szText then
			return txt:GetText()
		end
		if self.type == "WndTrackBar" then
			local scroll = self.self:Lookup("Scroll_Track")
			scroll.szText = szText
			txt:SetText(scroll.nVal .. scroll.szText)
		elseif self.type == "WndEdit" and bDummy then
			local fnChanged = txt.OnEditChanged
			txt.OnEditChanged = nil
			txt:SetText(szText)
			txt.OnEditChanged = fnChanged
		else
			txt:SetText(szText)
		end
		if self.type == "WndTabBox" then
			self:AutoSize()
		end
	end
	return self
end

-- (boolean) Instance:Multi()
-- (self) Instance:Multi(boolean bEnable)
-- NOTICE: only for WndEdit
function _HM.UI.Wnd:Multi(bEnable)
	local edit = self.edit
	if edit then
		if bEnable == nil then
			return edit:IsMultiLine()
		end
		edit:SetMultiLine(bEnable == true)
	end
	return self
end

-- (number) Instance:Limit()
-- (self) Instance:Limit(number nLimit)
-- NOTICE: only for WndEdit
function _HM.UI.Wnd:Limit(nLimit)
	local edit = self.edit
	if edit then
		if not nLimit then
			return edit:GetLimit()
		end
		edit:SetLimit(nLimit)
	end
	return self
end

-- (self) Instance:Change()			-- 触发编辑框修改处理函数
-- (self) Instance:Change(func fnAction)
-- NOTICE：only for WndEdit，WndTrackBar
function _HM.UI.Wnd:Change(fnAction)
	if self.type == "WndTrackBar" then
		self.self:Lookup("Scroll_Track").OnScrollBarPosChanged_ = fnAction
	elseif self.edit then
		local edit = self.edit
		if not fnAction then
			if edit.OnEditChanged then
				local _this = this
				this = edit
				edit.OnEditChanged()
				this = _this
			end
		else
			edit.OnEditChanged = function()
				if not this.bChanging then
					this.bChanging = true
					fnAction(this:GetText())
					this.bChanging = false
				end
			end
		end
	end
	return self
end

-- (self) Instance:Menu(table menu)		-- 设置下拉菜单
-- NOTICE：only for WndComboBox
function _HM.UI.Wnd:Menu(menu)
	if self.type == "WndComboBox" then
		local wnd = self.self
		self:Click(function()
			local _menu = nil
			local nX, nY = wnd:GetAbsPos()
			local nW, nH = wnd:GetSize()
			if type(menu) == "function" then
				_menu = menu()
			else
				_menu = menu
			end
			_menu.nMiniWidth = nW
			_menu.x = nX
			_menu.y = nY + nH
			PopupMenu(_menu)
		end)
	end
	return self
end

-- (self) Instance:Click()
-- (self) Instance:Click(func fnAction)	-- 设置组件点击后触发执行的函数
-- fnAction = function([bCheck])			-- 对于 WndCheckBox 会传入 bCheck 代表是否勾选
function _HM.UI.Wnd:Click(fnAction)
	local wnd = self.self
	if self.type == "WndComboBox" then
		wnd = wnd:Lookup("Btn_ComboBox")
	end
	if wnd:GetType() == "WndCheckBox" then
		if not fnAction then
			self:Check(not self:Check())
		else
			wnd.OnCheckBoxCheck = function()
				if wnd.group then
					local uis = this:GetParent().___uis or {}
					for _, ui in pairs(uis) do
						if ui:Group() == this.group and ui:Name() ~= this:GetName() then
							ui:Check(false)
						end
					end
				end
				fnAction(true)
			end
			wnd.OnCheckBoxUncheck = function() fnAction(false) end
		end
	else
		if not fnAction then
			if wnd.OnLButtonClick then
				local _this = this
				this = wnd
				wnd.OnLButtonClick()
				this = _this
			end
		else
			wnd.OnLButtonClick = fnAction
		end
	end
	return self
end

-- (self) Instance:Hover(func fnEnter[, func fnLeave])	-- 设置鼠标进出处理函数
-- fnEnter = function(true)		-- 鼠标进入时调用
-- fnLeave = function(false)		-- 鼠标移出时调用，若省略则和进入函数一样
function _HM.UI.Wnd:Hover(fnEnter, fnLeave)
	local wnd = wnd
	if self.type == "WndComboBox" then
		wnd = wnd:Lookup("Btn_ComboBox")
	end
	if wnd then
		fnLeave = fnLeave or fnEnter
		if fnEnter then
			wnd.OnMouseEnter = function() fnEnter(true) end
		end
		if fnLeave then
			wnd.OnMouseLeave = function() fnLeave(false) end
		end
	end
	return self
end

-------------------------------------
-- Handle Item
-------------------------------------
_HM.UI.Item = class(_HM.UI.Base)

-- xml string
_HM.UI.tItemXML = {
	["Text"] = "<text>w=150 h=30 valign=1 font=162 eventid=257 </text>",
	["Image"] = "<image>w=100 h=100 eventid=257 </image>",
	["Box"] = "<box>w=48 h=48 eventid=525311 </text>",
	["Shadow"] = "<shadow>w=15 h=15 eventid=277 </shadow>",
	["Handle"] = "<handle>w=10 h=10</handle>",
	["Label"] = "<handle>w=150 h=30 eventid=257 <text>name=\"Text_Label\" w=150 h=30 font=162 valign=1 </text></handle>",
}

-- construct
function _HM.UI.Item:ctor(pHandle, szType, szName)
	local hnd = nil
	if not szType and not szName then
		-- convert from raw object
		hnd, szType = pHandle, pHandle:GetType()
	else
		local szXml = _HM.UI.tItemXML[szType]
		if szXml then
			-- append from xml
			local nCount = pHandle:GetItemCount()
			pHandle:AppendItemFromString(szXml)
			hnd = pHandle:Lookup(nCount)
			if hnd then hnd:SetName(szName) end
		else
			-- append from ini
			hnd = pHandle:AppendItemFromIni("interface\\HM\\ui\\HandleItems.ini","Handle_" .. szType, szName)
		end
		if not hnd then
			return HM.Sysmsg(_L("Unable to append handle item [%s]", szType))
		end
	end
	if szType == "BoxButton" then
		self.txt = hnd:Lookup("Text_BoxButton")
		self.img = hnd:Lookup("Image_BoxIco")
		hnd.OnItemMouseEnter = function()
			if not this.bSelected then
				this:Lookup("Image_BoxBg"):Hide()
				this:Lookup("Image_BoxBgOver"):Show()
			end
		end
		hnd.OnItemMouseLeave = function()
			if not this.bSelected then
				this:Lookup("Image_BoxBg"):Show()
				this:Lookup("Image_BoxBgOver"):Hide()
			end
		end
	elseif szType == "TxtButton" then
		self.txt = hnd:Lookup("Text_TxtButton")
		self.img = hnd:Lookup("Image_TxtBg")
		hnd.OnItemMouseEnter = function()
			self.img:Show()
		end
		hnd.OnItemMouseLeave = function()
			if not this.bSelected then
				self.img:Hide()
			end
		end
	elseif szType == "Label" then
		self.txt = hnd:Lookup("Text_Label")
	elseif szType == "Text" then
		self.txt = hnd
	elseif szType == "Image" then
		self.img = hnd
	end
	self.self, self.type = hnd, szType
	hnd:SetRelPos(0, 0)
	hnd:GetParent():FormatAllItemPos()
end

-- (number, number) Instance:Size()
-- (self) Instance:Size(number nW, number nH)
function _HM.UI.Item:Size(nW, nH)
	local hnd = self.self
	if not nW then
		local nW, nH = hnd:GetSize()
		if self.type == "Text" or self.type == "Label" then
			nW, nH = self.txt:GetTextExtent()
		end
		return nW, nH
	end
	hnd:SetSize(nW, nH)
	if self.type == "BoxButton" then
		local nPad = math.ceil(nH * 0.2)
		hnd:Lookup("Image_BoxBg"):SetSize(nW - 12, nH + 8)
		hnd:Lookup("Image_BoxBgOver"):SetSize(nW - 12, nH + 8)
		hnd:Lookup("Image_BoxBgSel"):SetSize(nW - 1, nH + 11)
		self.img:SetSize(nH - nPad, nH - nPad)
		self.img:SetRelPos(10, math.ceil(nPad / 2))
		self.txt:SetSize(nW - nH - nPad, nH)
		self.txt:SetRelPos(nH + 10, 0)
		hnd:FormatAllItemPos()
	elseif self.type == "TxtButton" then
		self.img:SetSize(nW, nH - 5)
		self.txt:SetSize(nW - 10, nH - 5)
	elseif self.type == "Label" then
		self.txt:SetSize(nW, nH)
	end
	return self
end

-- (self) Instance:Zoom(boolean bEnable)	-- 是否启用点击后放大
-- NOTICE：only for BoxButton
function _HM.UI.Item:Zoom(bEnable)
	local hnd = self.self
	if self.type == "BoxButton" then
		local bg = hnd:Lookup("Image_BoxBg")
		local sel = hnd:Lookup("Image_BoxBgSel")
		if bEnable == true then
			local nW, nH = bg:GetSize()
			sel:SetSize(nW + 11, nH + 3)
			sel:SetRelPos(1, -5)
		else
			sel:SetSize(bg:GetSize())
			sel:SetRelPos(5, -2)
		end
		hnd:FormatAllItemPos()
	end
	return self
end

-- (self) Instance:Select()		-- 激活选中当前按纽，进行特效处理
-- NOTICE：only for BoxButton，TxtButton
function _HM.UI.Item:Select()
	local hnd = self.self
	if self.type == "BoxButton" or self.type == "TxtButton" then
		local hParent, nIndex = hnd:GetParent(), hnd:GetIndex()
		local nCount = hParent:GetItemCount() - 1
		for i = 0, nCount do
			local item = HM.UI.Fetch(hParent:Lookup(i))
			if item and item.type == self.type then
				if i == nIndex then
					if not item.self.bSelected then
						hnd.bSelected = true
						hnd.nIndex = i
						if self.type == "BoxButton" then
							hnd:Lookup("Image_BoxBg"):Hide()
							hnd:Lookup("Image_BoxBgOver"):Hide()
							hnd:Lookup("Image_BoxBgSel"):Show()
							self.txt:SetFontScheme(65)
							local icon = hnd:Lookup("Image_BoxIco")
							local nW, nH = icon:GetSize()
							local nX, nY = icon:GetRelPos()
							icon:SetSize(nW + 8, nH + 8)
							icon:SetRelPos(nX - 3, nY - 5)
							hnd:FormatAllItemPos()
						else
							self.img:Show()
						end
					end
				elseif item.self.bSelected then
					item.self.bSelected = false
					if item.type == "BoxButton" then
						item.self:SetIndex(item.self.nIndex)
						if hnd.nIndex >= item.self.nIndex then
							hnd.nIndex = hnd.nIndex + 1
						end
						item.self:Lookup("Image_BoxBg"):Show()
						item.self:Lookup("Image_BoxBgOver"):Hide()
						item.self:Lookup("Image_BoxBgSel"):Hide()
						item.txt:SetFontScheme(163)
						local icon = item.self:Lookup("Image_BoxIco")
						local nW, nH = icon:GetSize()
						local nX, nY = icon:GetRelPos()
						icon:SetSize(nW - 8, nH - 8)
						icon:SetRelPos(nX + 3, nY + 5)
						item.self:FormatAllItemPos()
					else
						item.img:Hide()
					end
				end
			end
		end
		if hnd.nIndex then
			hnd:SetIndex(nCount)
		end
	end
	return self
end

-- (string) Instance:Text()
-- (self) Instance:Text(string szText)
function _HM.UI.Item:Text(szText)
	local txt = self.txt
	if txt then
		if not szText then
			return txt:GetText()
		end
		txt:SetText(szText)
	end
	return self
end

-- (boolean) Instance:Multi()
-- (self) Instance:Multi(boolean bEnable)
-- NOTICE: only for Text，Label
function _HM.UI.Item:Multi(bEnable)
	local txt = self.txt
	if txt then
		if bEnable == nil then
			return txt:IsMultiLine()
		end
		txt:SetMultiLine(bEnable == true)
	end
	return self
end

-- (self) Instance:File(string szUitexFile, number nFrame)
-- (self) Instance:File(string szTextureFile)
-- (self) Instance:File(number dwIcon)
-- NOTICE：only for Image，BoxButton
function _HM.UI.Item:File(szFile, nFrame)
	local img = nil
	if self.type == "Image" then
		img = self.self
	elseif self.type == "BoxButton" then
		img = self.img
	end
	if img then
		if type(szFile) == "number" then
			img:FromIconID(szFile)
		elseif not nFrame then
			img:FromTextureFile(szFile)
		else
			img:FromUITex(szFile, nFrame)
		end
	end
	return self
end

-- (self) Instance:Type()
-- (self) Instance:Type(number nType)		-- 修改图片类型或 BoxButton 的背景类型
-- NOTICE：only for Image，BoxButton
function _HM.UI.Item:Type(nType)
	local hnd = self.self
	if self.type == "Image" then
		if not nType then
			return hnd:GetImageType()
		end
		hnd:SetImageType(nType)
	elseif self.type == "BoxButton" then
		if nType == nil then
			local nFrame = hnd:Lookup("Image_BoxBg"):GetFrame()
			if nFrame == 16 then
				return 2
			elseif nFrame == 18 then
				return 1
			end
			return 0
		elseif nType == 0 then
			hnd:Lookup("Image_BoxBg"):SetFrame(1)
			hnd:Lookup("Image_BoxBgOver"):SetFrame(2)
			hnd:Lookup("Image_BoxBgSel"):SetFrame(3)
		elseif nType == 1 then
			hnd:Lookup("Image_BoxBg"):SetFrame(18)
			hnd:Lookup("Image_BoxBgOver"):SetFrame(19)
			hnd:Lookup("Image_BoxBgSel"):SetFrame(22)
		elseif nType == 2 then
			hnd:Lookup("Image_BoxBg"):SetFrame(16)
			hnd:Lookup("Image_BoxBgOver"):SetFrame(17)
			hnd:Lookup("Image_BoxBgSel"):SetFrame(15)
		end
	end
	return self
end

-- (self) Instance:Icon(number dwIcon)
-- NOTICE：only for Box，Image，BoxButton
function _HM.UI.Item:Icon(dwIcon)
	if self.type == "BoxButton" or self.type == "Image" then
		self.img:FromIconID(dwIcon)
	elseif self.type == "Box" then
		self.self:SetObjectIcon(dwIcon)
	end
	return self
end

-- (self) Instance:Click()
-- (self) Instance:Click(func fnAction[, boolean bSound[, boolean bSelect]])	-- 登记鼠标点击处理函数
-- (self) Instance:Click(func fnAction[, table tLinkColor[, tHoverColor]])		-- 同上，只对文本
function _HM.UI.Item:Click(fnAction, bSound, bSelect)
	local hnd = self.self
	--hnd:RegisterEvent(0x001)
	if not fnAction then
		if hnd.OnItemLButtonDown then
			local _this = this
			this = hnd
			hnd.OnItemLButtonDown()
			_this = this
		end
	elseif self.type == "BoxButton" or self.type == "TxtButton" then
		hnd.OnItemLButtonDown = function()
			if bSound then PlaySound(SOUND.UI_SOUND, g_sound.Button) end
			if bSelect then self:Select() end
			fnAction()
		end
	else
		hnd.OnItemLButtonDown = fnAction
		-- text link：tLinkColor，tHoverColor
		local txt = self.txt
		if txt then
			local tLinkColor = bSound or { 255, 255, 0 }
			local tHoverColor = bSelect or { 255, 200, 100 }
			txt:SetFontColor(unpack(tLinkColor))
			if tHoverColor then
				self:Hover(function(bIn)
					if bIn then
						txt:SetFontColor(unpack(tHoverColor))
					else
						txt:SetFontColor(unpack(tLinkColor))
					end
				end)
			end
		end
	end
	return self
end

-- (self) Instance:Hover(func fnEnter[, func fnLeave])	-- 设置鼠标进出处理函数
-- fnEnter = function(true)		-- 鼠标进入时调用
-- fnLeave = function(false)		-- 鼠标移出时调用，若省略则和进入函数一样
function _HM.UI.Item:Hover(fnEnter, fnLeave)
	local hnd = self.self
	--hnd:RegisterEvent(0x300)
	fnLeave = fnLeave or fnEnter
	if fnEnter then
		hnd.OnItemMouseEnter = function() fnEnter(true) end
	end
	if fnLeave then
		hnd.OnItemMouseLeave = function() fnLeave(false) end
	end
	return self
end

---------------------------------------------------------------------
-- 公开的 API：HM.UI.xxx
---------------------------------------------------------------------
HM.UI = {}

-- 设置元表，这样可以当作函数调用，其效果相当于 HM.UI.Fetch
setmetatable(HM.UI, { __call = function(me, ...) return me.Fetch(...) end, __metatable = true })

-- 开启一个空的对话窗体界面，并返回 HM.UI 封装对象
-- (class) HM.UI.OpenFrame([string szName, ]table tArg)
-- szName		-- *可选* 名称，若省略则自动编序号
-- tArg {			-- *可选* 初始化配置参数，自动调用相应的封装方法，所有属性均可选
--		w, h,			-- 宽和高，成对出现用于指定大小，注意宽度会自动被就近调节为：770/380/234，高度最小 200
--		x, y,			-- 位置坐标，默认在屏幕正中间
--		title			-- 窗体标题
--		drag			-- 设置窗体是否可拖动
--		close		-- 点击关闭按纽是是否真正关闭窗体（若为 false 则是隐藏）
--		empty		-- 创建空窗体，不带背景，全透明，只是界面需求
--		fnCreate = function(frame)		-- 打开窗体后的初始化函数，frame 为内容窗体，在此设计 UI
--		fnDestroy = function(frame)	-- 关闭销毁窗体时调用，frame 为内容窗体，可在此清理变量
-- }
-- 返回值：通用的  HM.UI 对象，可直接调用封装方法
HM.UI.CreateFrame = function(szName, tArg)
	if type(szName) == "table" then
		szName, tArg = nil, szName
	end
	tArg = tArg or {}
	local ui = _HM.UI.Frm.new(szName, tArg.empty == true)
	-- apply init setting
	if tArg.w and tArg.h then ui:Size(tArg.w, tArg.h) end
	if tArg.x and tArg.y then ui:Pos(tArg.x, tArg.y) end
	if tArg.title then ui:Title(tArg.title) end
	if tArg.drag ~= nil then ui:Drag(tArg.drag) end
	if tArg.close ~= nil then ui.self.bClose = tArg.close end
	if tArg.fnCreate then tArg.fnCreate(ui:Raw()) end
	if tArg.fnDestroy then ui.fnDestroy = tArg.fnDestroy end
	if tArg.parent then ui:Relation(tArg.parent) end
	return ui
end

-- 创建空窗体
HM.UI.CreateFrameEmpty = function(szName, szParent)
	return HM.UI.CreateFrame(szName, { empty  = true, parent = szParent })
end

-- 往某一父窗体或容器添加  INI 配置文件中的部分，并返回 HM.UI 封装对象
-- (class) HM.UI.Append(userdata hParent, string szIniFile, string szTag, string szName)
-- hParent		-- 父窗体或容器原始对象（HM.UI 对象请直接用  :Append 方法）
-- szIniFile		-- INI 文件路径
-- szTag			-- 要添加的对象源，即中括号内的部分 [XXXX]，请与 hParent 匹配采用 Wnd 或容器组件
-- szName		-- *可选* 对象名称，若不指定则沿用原名称
-- 返回值：通用的  HM.UI 对象，可直接调用封装方法，失败或出错返回 nil
-- 特别注意：这个函数也支持添加窗体对象
HM.UI.AppendIni = function(hParent, szFile, szTag, szName)
	local raw = nil
	if hParent:GetType() == "Handle" then
		if not szName then
			szName = "Child_" .. hParent:GetItemCount()
		end
		raw = hParent:AppendItemFromIni(szFile, szTag, szName)
	elseif string.sub(hParent:GetType(), 1, 3) == "Wnd" then
		local frame = Wnd.OpenWindow(szFile, "HM_Virtual")
		if frame then
			raw = frame:Lookup(szTag)
			if raw and string.sub(raw:GetType(), 1, 3) == "Wnd" then
				raw:ChangeRelation(hParent, true, true)
				if szName then
					raw:SetName(szName)
				end
			else
				raw = nil
			end
			Wnd.CloseWindow(frame)
		end
	end
	if not raw then
		HM.Sysmsg(_L("Fail to add component [%s@%s]", szTag, szFile))
	else
		return HM.UI.Fetch(raw)
	end
end

-- 往某一父窗体或容器添加 HM.UI 组件并返回封装对象
-- (class) HM.UI.Append(userdata hParent, string szType[, string szName], table tArg)
-- hParent		-- 父窗体或容器原始对象（HM.UI 对象请直接用  :Append 方法）
-- szType			-- 要添加的组件类型（如：WndWindow，WndEdit，Handle，Text ……）
-- szName		-- *可选* 名称，若省略则自动编序号
-- tArg {			-- *可选* 初始化配置参数，自动调用相应的封装方法，所有属性均可选，如果没用则忽略
--		w, h,			-- 宽和高，成对出现用于指定大小
--		x, y,			-- 位置坐标
--		txt, font, multi, limit, align		-- 文本内容，字体，是否多行，长度限制，对齐方式（0：左，1：中，2：右）
--		color, alpha			-- 颜色，不透明度
--		checked				-- 是否勾选，CheckBox 专用
--		enable					-- 是否启用
--		file, icon, type		-- 图片文件地址，图标编号，类型
--		group					-- 单选框分组设置
-- }
-- 返回值：通用的  HM.UI 对象，可直接调用封装方法，失败或出错返回 nil
-- 特别注意：为统一接口此函数也可用于 AppendIni 文件，参数与 HM.UI.AppendIni 一致
-- (class) HM.UI.Append(userdata hParent, string szIniFile, string szTag, string szName)
HM.UI.Append = function(hParent, szType, szName, tArg)
	-- compatiable with AppendIni
	if StringFindW(szType, ".ini") ~= nil then
		return HM.UI.AppendIni(hParent, szType, szName, tArg)
	end
	-- reset parameters
	if not tArg and type(szName) == "table" then
		szName, tArg = nil, szName
	end
	if not szName then
		if not hParent.nAutoIndex then
			hParent.nAutoIndex = 1
		end
		szName = szType .. "_" .. hParent.nAutoIndex
		hParent.nAutoIndex = hParent.nAutoIndex + 1
	else
		szName = tostring(szName)
	end
	-- create ui
	local ui = nil
	if string.sub(szType, 1, 3) == "Wnd" then
		if string.sub(hParent:GetType(), 1, 3) ~= "Wnd" then
			return HM.Sysmsg(_L["The 1st arg for adding component must be a [WndXxx]"])
		end
		ui = _HM.UI.Wnd.new(hParent, szType, szName)
	else
		if hParent:GetType() ~= "Handle" then
			return HM.Sysmsg(_L["The 1st arg for adding item must be a [Handle]"])
		end
		ui = _HM.UI.Item.new(hParent, szType, szName)
	end
	local raw = ui:Raw()
	if raw then
		-- for reverse fetching
		hParent.___uis = hParent.___uis or {}
		for k, v in pairs(hParent.___uis) do
			if not v.self.___id then
				hParent.___uis[k] = nil
			end
		end
		hParent.___uis[szName] = ui
		hParent.___last = szName
		-- apply init setting
		tArg = tArg or {}
		if tArg.w and tArg.h then ui:Size(tArg.w, tArg.h) end
		if tArg.x and tArg.y then ui:Pos(tArg.x, tArg.y) end
		if tArg.font then ui:Font(tArg.font) end
		if tArg.multi ~= nil then ui:Multi(tArg.multi) end
		if tArg.limit then ui:Limit(tArg.limit) end
		if tArg.color then ui:Color(unpack(tArg.color)) end
		if tArg.align ~= nil then ui:Align(tArg.align) end
		if tArg.alpha then ui:Alpha(tArg.alpha) end
		if tArg.txt then ui:Text(tArg.txt) end
		if tArg.checked ~= nil then ui:Check(tArg.checked) end
		-- wnd only
		if tArg.enable ~= nil then ui:Enable(tArg.enable) end
		if tArg.group then ui:Group(tArg.group) end
		if ui.type == "WndComboBox" and (not tArg.w or not tArg.h) then
			ui:Size(185, 25)
		end
		-- item only
		if tArg.file then ui:File(tArg.file, tArg.num) end
		if tArg.icon ~= nil then ui:Icon(tArg.icon) end
		if tArg.type then ui:Type(tArg.type) end
		return ui
	end
end

-- (class) HM.UI(...)
-- (class) HM.UI.Fetch(hRaw)						-- 将 hRaw 原始对象转换为 HM.UI 封装对象
-- (class) HM.UI.Fetch(hParent, szName)	-- 从 hParent 中提取名为 szName 的子元件并转换为 HM.UI 对象
-- 返回值：通用的  HM.UI 对象，可直接调用封装方法，失败或出错返回 nil
HM.UI.Fetch = function(hParent, szName)
	if type(hParent) == "string" then
		hParent = Station.Lookup(hParent)
	end
	if not szName then
		szName = hParent:GetName()
		hParent = hParent:GetParent()
	end
	-- exists
	if hParent.___uis and hParent.___uis[szName] then
		local ui = hParent.___uis[szName]
		if ui and ui.self.___id then
			return ui
		end
	end
	-- convert
	local hRaw = hParent:Lookup(szName)
	if hRaw then
		local ui
		if string.sub(hRaw:GetType(), 1, 3) == "Wnd" then
			ui = _HM.UI.Wnd.new(hRaw)
		else
			ui = _HM.UI.Item.new(hRaw)
		end
		hParent.___uis = hParent.___uis or {}
		hParent.___uis[szName] = ui
		return ui
	end
end

---------------------------------------------------------------------
-- 主窗体界面回调函数 HM.OnXXX
---------------------------------------------------------------------
-- create frame
HM.OnFrameCreate = function()
	-- var
	_HM.frame = this
	_HM.hTotal = this:Lookup("Wnd_Content", "")
	_HM.hScroll = this:Lookup("Wnd_Content/Scroll_List")
	_HM.hList = _HM.hTotal:Lookup("Handle_List")
	_HM.hContent = _HM.hTotal:Lookup("Handle_Content")
	_HM.hBox = _HM.hTotal:Lookup("Box_1")
	-- title
	local szTitle =_HM.szTitle .. " v" .. HM.GetVersion() .. " (" .. HM.szBuildDate .. ")"
	_HM.hTotal:Lookup("Text_Title"):SetText(szTitle)
	-- position
	this:SetPoint("CENTER", 0, 0, "CENTER", 0, 0)
	-- update list/detail
	_HM.UpdateTabBox(this)
	--_HM.UpdateDetail()
end

-- breathe
HM.OnFrameBreathe = function()
	-- run breathe calls
	local nFrame = GetLogicFrameCount()
	for k, v in pairs(_HM.tBreatheCall) do
		if nFrame >= v.nNext then
			v.nNext = nFrame + v.nFrame
			local res, err = pcall(v.fnAction)
			if not res then
				HM.Debug("BreatheCall#" .. k .." ERROR: " .. err)
			end
		end
	end
	-- run delay calls
	local nTime = GetTime()
	for k = #_HM.tDelayCall, 1, -1 do
		local v = _HM.tDelayCall[k]
		if v.nTime <= nTime then
			local res, err = pcall(v.fnAction)
			if not res then
				HM.Debug("DelayCall#" .. k .." ERROR: " .. err)
			end
			table.remove(_HM.tDelayCall, k)
		end
	end
	-- run player monitor
	_HM.SetTempTarget()
end

-- key down
HM.OnFrameKeyDown = function()
	if GetKeyName(Station.GetMessageKey()) == "Esc" then
		_HM.ClosePanel()
		return 1
	end
	return 0
end

-- button click
HM.OnLButtonClick = function()
	local szName = this:GetName()
	if szName == "Btn_Close" then
		_HM.ClosePanel()
	elseif szName == "Btn_Up" then
		_HM.hScroll:ScrollPrev(1)
	elseif szName == "Btn_Down" then
		_HM.hScroll:ScrollNext(1)
	end
end

-- scrolls
HM.OnScrollBarPosChanged = function()
	local handle, frame = _HM.hList, this:GetParent()
	local nPos = this:GetScrollPos()
	if nPos == 0 then
		frame:Lookup("Btn_Up"):Enable(0)
	else
		frame:Lookup("Btn_Up"):Enable(1)
	end
	if nPos == this:GetStepCount() then
		frame:Lookup("Btn_Down"):Enable(0)
	else
		frame:Lookup("Btn_Down"):Enable(1)
	end
    handle:SetItemStartRelPos(0, - nPos * 10)
end

-- web page title changed
HM.OnTitleChanged = function()
	local szUrl, szTitle = this:GetLocationURL(), this:GetLocationName()
	if szUrl ~= szTitle and _HM.tRequest[szUrl] then
		local fnAction = _HM.tRequest[szUrl]
		fnAction(szTitle)
		_HM.tRequest[szUrl] = nil
	end
end

---------------------------------------------------------------------
-- 注册事件、初始化
---------------------------------------------------------------------
HM.RegisterEvent("PLAYER_ENTER_GAME", _HM.Init)
HM.RegisterEvent("LOADING_END", function()
	if _HM.tConflict then
		for _, v in ipairs(_HM.tConflict) do v() end
		_HM.tConflict = nil
		HM.Sysmsg(_L("%s are welcome to use HM plug-in", GetClientPlayer().szName) .. "/" .. HM.GetVersion())
	end
	-- reseting frame count (FIXED BUG FOR Cross Server)
	_HM.nTempFrame = nil
	for k, v in pairs(_HM.tBreatheCall) do
		v.nNext = GetLogicFrameCount()
	end
end)
HM.RegisterEvent("PLAYER_ENTER_SCENE", function() _HM.aPlayer[arg0] = true end)
HM.RegisterEvent("PLAYER_LEAVE_SCENE", function() _HM.aPlayer[arg0] = nil end)
HM.RegisterEvent("NPC_ENTER_SCENE", function() _HM.aNpc[arg0] = true end)
HM.RegisterEvent("NPC_LEAVE_SCENE", function() _HM.aNpc[arg0] = nil end)
HM.RegisterEvent("DOODAD_ENTER_SCENE", function() _HM.aDoodad[arg0] = true end)
HM.RegisterEvent("DOODAD_LEAVE_SCENE", function() _HM.aDoodad[arg0] = nil end)
HM.RegisterEvent("CUSTOM_DATA_LOADED", function()
	if arg0 == "Role" then
		for _, v in ipairs(_HM.tCustomUpdateCall) do
			if not v.nDate or v.nDate > HM.nBuildDate then
				v.fnAction()
			end
		end
		HM.nBuildDate = tonumber(_HM.szBuildDate)
	end
end)

-- player menu
HM.AppendPlayerMenu(function()
	return {
		szOption = _L["Open HM setting panel"] .. HM.GetHotKey("Total", true),
		bCheck = true, bChecked = _HM.frame and _HM.frame:IsVisible(),
		fnAction = _HM.TogglePanel
	}
end)
