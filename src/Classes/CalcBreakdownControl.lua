-- Path of Building
--
-- Class: Calc Breakdown Control
-- Calculation breakdown control used in the Calcs tab
--
local t_insert = table.insert
local m_max = math.max
local m_min = math.min
local m_ceil = math.ceil
local m_floor = math.floor
local m_sin = math.sin
local m_cos = math.cos
local m_pi = math.pi
local band = bit.band

local CalcBreakdownClass = newClass("CalcBreakdownControl", "Control", "ControlHost", function(self, calcsTab)
	self.Control()
	self.ControlHost()
	self.calcsTab = calcsTab
	self.shown = false
	self.tooltip = new("Tooltip")
	self.nodeViewer = new("PassiveTreeView")
	self.rangeGuide = NewImageHandle()
	self.rangeGuide:Load("Assets/range_guide.png")
	self.uiOverlay = NewImageHandle()
	self.uiOverlay:Load("Assets/game_ui_small.png")
	self.controls.scrollBar = new("ScrollBarControl", {"RIGHT",self,"RIGHT"}, -2, 0, 18, 0, 80, "VERTICAL", true)
end)

function CalcBreakdownClass:IsMouseOver()
	if not self:IsShown() then
		return
	end
	return self:IsMouseInBounds() or self:GetMouseOverControl() 
end

function CalcBreakdownClass:SetBreakdownData(displayData, pinned)
	self.pinned = pinned
	if displayData == self.sourceData then
		return
	end
	self.sourceData = displayData
	self.shown = false
	if not displayData then
		return
	end

	-- Build list of sections
	self.sectionList = wipeTable(self.sectionList)
	for _, sectionData in ipairs(displayData) do
		if self.calcsTab:CheckFlag(sectionData) then
			if sectionData.breakdown then
				self:AddBreakdownSection(sectionData)
			elseif sectionData.modName then
				self:AddModSection(sectionData)
			end
		end
	end
	if #self.sectionList == 0 then
		self.calcsTab:ClearDisplayStat()
		return
	end

	self.shown = true

	-- Determine the size of each section, and the combined content size of the breakdown
	self.contentWidth = 0
	local offset = 2
	for i, section in ipairs(self.sectionList) do
		if section.type == "TEXT" then
			section.width = 0
			for _, line in ipairs(section.lines) do
				local _, num = string.gsub(line, "%d%d%d%d", "") -- count how many commas will be added
				if main.showThousandsSeparators and num > 0 then
					section.width = m_max(section.width, DrawStringWidth(section.textSize, "VAR", line) + 8 + (4 * num))
				else
					section.width = m_max(section.width, DrawStringWidth(section.textSize, "VAR", line) + 8)
				end
			end
			section.height = #section.lines * section.textSize + 4
		elseif section.type == "TABLE" then
			-- This also calculates the width of each column in the table
			section.width = 4
			for _, col in pairs(section.colList) do
				for _, row in pairs(section.rowList) do
					if row[col.key] then
						local _, num = string.gsub(row[col.key], "%d%d%d%d", "") -- count how many commas will be added
						if main.showThousandsSeparators and num > 0 then
							col.width = m_max(col.width or 0, DrawStringWidth(16, "VAR", col.label) + 6, DrawStringWidth(12, "VAR", row[col.key]) + 6 + (4 * num))
						else 
							col.width = m_max(col.width or 0, DrawStringWidth(16, "VAR", col.label) + 6, DrawStringWidth(12, "VAR", row[col.key]) + 6)
						end
					end
				end
				if col.width then
					section.width = section.width + col.width
				end
			end
			section.height = #section.rowList * 14 + 20
			if section.label then
				self.contentWidth = m_max(self.contentWidth, 6 + DrawStringWidth(16, "VAR", section.label..":"))
				section.height = section.height + 16
			end
			if section.footer then
				self.contentWidth = m_max(self.contentWidth, 6 + DrawStringWidth(12, "VAR", section.footer))
				local _, lines = string.gsub(section.footer, "\n", "\n") -- counts newlines in the string
				section.height = section.height + 12 * (lines + 1)
			end
		end
		self.contentWidth = m_max(self.contentWidth, section.width)
		section.offset = offset
		offset = offset + section.height + 8
	end
	self.contentHeight = offset - 6
end

-- Add sections based on the breakdown data generated by the Calcs module
function CalcBreakdownClass:AddBreakdownSection(sectionData)
	local actor = self.calcsTab.input.showMinion and self.calcsTab.calcsEnv.minion or self.calcsTab.calcsEnv.player
	local breakdown
	local ns, name = sectionData.breakdown:match("^(%a+)%.(%a+)$")
	if ns then
		breakdown = actor.breakdown[ns] and actor.breakdown[ns][name]
	else
		breakdown = actor.breakdown[sectionData.breakdown]
	end
	if not breakdown then
		return
	end

	if #breakdown > 0 then
		-- Text lines
		t_insert(self.sectionList, {
			type = "TEXT",
			lines = breakdown,
			textSize = 16
		})
	end

	if breakdown.radius then
		-- Radius visualiser
		t_insert(self.sectionList, {
			type = "RADIUS",
			radius = breakdown.radius,
			width = 8 + 1920/4,
			height = 4 + 1080/4,
		})
	end

	if breakdown.rowList and #breakdown.rowList > 0 then
		-- sort by the first column (the value)
		local rowList = copyTable(breakdown.rowList, true)
		local colKey = breakdown.colList[1].key
		table.sort(rowList, function(a, b)
			if a.reqNum then
				return a.reqNum > b.reqNum
			end
			return a[colKey] > b[colKey]
		end)
		
		-- Generic table
		local section = {
			type = "TABLE",
			label = breakdown.label,
			footer = breakdown.footer,
			rowList = rowList,
			colList = breakdown.colList,
		}
		t_insert(self.sectionList, section)
	end

	if breakdown.reservations and #breakdown.reservations > 0 then
		-- Reservations table, used for life/mana reservation breakdowns
		local section = {
			type = "TABLE",
			rowList = breakdown.reservations,
			colList = { 
				{ label = "Skill", key = "skillName" },
				{ label = "Base", key = "base" },
				{ label = "MCM", key = "mult" },
				{ label = "More/less", key = "more" },
				{ label = "Inc/red", key = "inc" },
				{ label = "Efficiency", key = "efficiency" },
				{ label = "Reservation", key = "total" },
			}
		}
		t_insert(self.sectionList, section)
	end

	if breakdown.damageTypes and #breakdown.damageTypes > 0 then
		local section = {
			type = "TABLE",
			rowList = breakdown.damageTypes,
			colList = { 
				{ label = "From", key = "source", right = true },
				{ label = "Base", key = "base" },
				{ label = "Inc/red", key = "inc" },
				{ label = "More/less", key = "more" },
				{ label = "Converted Damage", key = "convSrc" },
				{ label = "Total", key = "total" },
				{ label = "Conversion", key = "convDst" },
			}
		}
		t_insert(self.sectionList, section)
	end

	if breakdown.slots and #breakdown.slots > 0 then
		-- Slots table, used for armour/evasion/ES total breakdowns
		local colList
		local rowList
		if (sectionData.gearOnly) then
			-- Only show basic table for gear and base ES/Armour/Evasion value
			colList = {
				{ label = "Value", key = "base", right = true },
				{ label = "Source", key = "source" },
				{ label = "Name", key = "sourceLabel" },
			}

			rowList = {}
			for _, row in pairs(breakdown.slots) do
				if (row.item and row.item.armourData) then
					table.insert(rowList, row)
				end
			end
		else
			colList = {
				{ label = "Base", key = "base", right = true },
				{ label = "Inc/red", key = "inc" },
				{ label = "More/less", key = "more" },
				{ label = "Total", key = "total", right = true },
				{ label = "Source", key = "source" },
				{ label = "Name", key = "sourceLabel" },
			}

			rowList = breakdown.slots
		end

		table.sort(rowList, function(a, b)
			return a['base'] > b['base']
		end)
		
		local section = { 
			type = "TABLE",
			rowList = rowList,
			colList = colList,
		}
		t_insert(self.sectionList, section)
		for _, row in pairs(section.rowList) do
			if row.item then
				row.sourceLabel = colorCodes[row.item.rarity]..row.item.name
				row.sourceLabelTooltip = function(tooltip)
					self.calcsTab.build.itemsTab:AddItemTooltip(tooltip, row.item, row.source)
				end
			else
				row.sourceLabel = row.sourceName
			end
		end
	end

	if breakdown.modList and #breakdown.modList > 0 then
		-- Provided mod list
		self:AddModSection(sectionData, breakdown.modList)
	end
end

-- Add a table section showing a list of modifiers
function CalcBreakdownClass:AddModSection(sectionData, modList)
	local actor = self.calcsTab.input.showMinion and self.calcsTab.calcsEnv.minion or self.calcsTab.calcsEnv.player
	local build = self.calcsTab.build

	-- Build list of modifiers to display
	local cfg = (sectionData.cfg and actor.mainSkill[sectionData.cfg.."Cfg"] and copyTable(actor.mainSkill[sectionData.cfg.."Cfg"], true)) or { }
	cfg.source = sectionData.modSource
	cfg.actor = sectionData.actor
	local rowList
	local modStore = (sectionData.enemy and actor.enemy.modDB) or (sectionData.cfg and actor.mainSkill.skillModList) or actor.modDB
	if modList then
		rowList = copyTable(modList)
	else
		if type(sectionData.modName) == "table" then
			rowList = modStore:Tabulate(sectionData.modType, cfg, unpack(sectionData.modName))
		else
			rowList = modStore:Tabulate(sectionData.modType, cfg, sectionData.modName)
		end
	end
	if #rowList == 0 then
		return
	end

	-- Create section data
	local section = {
		type = "TABLE",
		label = sectionData.label,
		rowList = rowList,
		colList = { 
			{ label = "Value", key = "displayValue" },
			{ label = "Stat", key = "name" },
			{ label = "Skill types", key = "flags" },
			{ label = "Notes", key = "tags" },
			{ label = "Source", key = "source" },
			{ label = "Source Name", key = "sourceName" },
		},
	}
	t_insert(self.sectionList, section)

	if not modList and not sectionData.modType then
		-- Sort modifiers by type
		table.sort(rowList, function(a, b)
			if a.mod.type == b.mod.type then
				return a.mod.name > b.mod.name or a.mod.name == b.mod.name and a.value > b.value
			else
				return a.mod.type < b.mod.type
			end
		end)
	else -- Sort modifiers by value
		table.sort(rowList, function(a, b)
			return a.mod.name > b.mod.name or a.mod.name == b.mod.name and a.value > b.value
		end)
	end

	local sourceTotals = { }
	if not modList and not sectionData.modSource then
		-- Build list of totals from each modifier source
		local types = { }
		local typeList = { }
		for i, row in ipairs(rowList) do
			-- Find all the modifier types and source types that are present in the modifier list
			if not types[row.mod.type] then
				types[row.mod.type] = true
				t_insert(typeList, row.mod.type)
			end
			if not row.mod.source then
				ConPrintTable(row.mod)
			end
			local sourceType = row.mod.source:match("[^:]+")
			if not sourceTotals[sourceType] then
				sourceTotals[sourceType] = { }
			end	
		end
		for sourceType, lines in pairs(sourceTotals) do
			cfg.source = sourceType
			for _, modType in ipairs(typeList) do
				if type(sectionData.modName) == "table" then
					-- Multiple stats, show each separately
					for _, modName in ipairs(sectionData.modName) do
						local total = modStore:Combine(modType, cfg, modName)
						if modType == "MORE" then
							total = round((total - 1) * 100)
						end
						if total and total ~= 0 then
							t_insert(lines, self:FormatModValue(total, modType) .. " " .. modName:gsub("(%l)(%u)","%1 %2"))
						end
					end
				else
					local total = modStore:Combine(modType, cfg, sectionData.modName)
					if modType == "MORE" then
						total = round((total - 1) * 100)
					end
					if total and total ~= 0 then
						t_insert(lines, self:FormatModValue(total, modType))
					end
				end
			end
		end
	end

	-- Process modifier data
	for _, row in ipairs(rowList) do
		if not sectionData.modType then
			-- No modifier type specified, so format the value to convey type
			row.displayValue = self:FormatModValue(row.value, row.mod.type)
		else
			section.colList[1].right = true
			row.displayValue = formatRound(row.value, 2)
		end
		if modList or type(sectionData.modName) == "table" then
			-- Multiple stat names specified, add this modifier's stat to the table
			row.name = self:FormatModName(row.mod.name)
		end
		local sourceType = row.mod.source:match("[^:]+")
		if not modList and not sectionData.modSource then
			-- No modifier source specified, add the source type to the table
			row.source = sourceType
			row.sourceTooltip = function(tooltip)
				tooltip:AddLine(16, "Total from "..sourceType..":")
				for _, line in ipairs(sourceTotals[sourceType]) do
					tooltip:AddLine(14, line)
				end
			end
		end
		if sourceType == "Item" then
			-- Modifier is from an item, add item name and tooltip
			local itemId = row.mod.source:match("Item:(%d+):.+")
			local item = build.itemsTab.items[tonumber(itemId)]
			if item then
				row.sourceName = colorCodes[item.rarity]..item.name
				row.sourceNameTooltip = function(tooltip)
					build.itemsTab:AddItemTooltip(tooltip, item, row.mod.sourceSlot)
				end
			end
		elseif sourceType == "Tree" then
			-- Modifier is from a passive node, add node name, and add node ID (used to show node location)
			local nodeId = row.mod.source:match("Tree:(%d+)")
			if nodeId then
				local nodeIdNumber = tonumber(nodeId)
				local node = build.spec.nodes[nodeIdNumber] or build.spec.tree.nodes[nodeIdNumber]
				row.sourceName = node.dn
				row.sourceNameNode = node
			end
		elseif sourceType == "Skill" then
			-- Extract skill name
			row.sourceName = build.data.skills[row.mod.source:match("Skill:(.+)")].name
		elseif sourceType == "Pantheon" then
			row.sourceName = row.mod.source:match("Pantheon:(.+)")
		elseif sourceType == "Spectre" then
			row.sourceName = row.mod.source:match("Spectre:(.+)")
		end

		if row.mod.flags ~= 0 or row.mod.keywordFlags ~= 0 then
			-- Combine, sort and format modifier flags
			local flagNames = { }
			for flags, src in pairs({[row.mod.flags] = ModFlag, [row.mod.keywordFlags] = KeywordFlag}) do
				for name, val in pairs(src) do
					if band(flags, val) == val then
						t_insert(flagNames, name)
					end
				end
			end
			table.sort(flagNames)
			row.flags = table.concat(flagNames, ", ")
		end
		row.tags = nil
		if row.mod[1] then
			-- Format modifier tags
			local baseVal = type(row.mod.value) == "number" and (self:FormatModBase(row.mod, row.mod.value) .. " ")
			for _, tag in ipairs(row.mod) do
				local desc
				if tag.type == "Condition" or tag.type == "ActorCondition" then
					local cond = (tag.var or tag.varList) and ": "..(tag.neg and "Not " or "")..self:FormatVarNameOrList(tag.var, tag.varList) or ""
					desc = (tag.actor and (tag.actor:sub(1,1):upper()..tag.actor:sub(2).." ") or "").."Condition"..cond
				elseif tag.type == "Multiplier" then
					local base = tag.base and (self:FormatModBase(row.mod, tag.base).." + "..math.abs(row.mod.value).." ") or baseVal
					desc = base.."per "..(tag.div and (tag.div.." ") or "")..self:FormatVarNameOrList(tag.var, tag.varList)
					baseVal = ""
				elseif tag.type == "PerStat" then
					local base = tag.base and (self:FormatModBase(row.mod, tag.base).." + "..math.abs(row.mod.value).." ") or baseVal
					desc = base.."per "..(tag.div or 1).." "..(tag.actor and (tag.actor.." ") or "")..self:FormatVarNameOrList(tag.stat, tag.statList)
					baseVal = ""
				elseif tag.type == "PercentStat" then
					local finalPercent = (row.mod.value * ((tag.percent or 1) / 100)) * 100
					local base = tag.base and (self:FormatModBase(row.mod, tag.base).." + "..math.abs(finalPercent).." ") or self:FormatModBase(row.mod, finalPercent)
					desc = base.."% of "..(tag.actor and (tag.actor.." ") or "")..self:FormatVarNameOrList(tag.percentVar or tag.stat, tag.statList)
					baseVal = ""
				elseif tag.type == "MultiplierThreshold" or tag.type == "StatThreshold" then
					desc = "If "..self:FormatVarNameOrList(tag.var or tag.stat, tag.varList or tag.statList)..(tag.upper and " <= " or " >= ")..(tag.thresholdPercent and tag.thresholdPercent.."% " or "")..(tag.threshold or self:FormatModName(tag.thresholdVar or tag.thresholdStat))
				elseif tag.type == "SkillName" then
					desc = "Skill: "..(tag.skillNameList and table.concat(tag.skillNameList, "/") or tag.skillName)
				elseif tag.type == "SkillId" then
					desc = "Skill: "..build.data.skills[tag.skillId].name
				elseif tag.type == "SkillType" then
					for name, type in pairs(SkillType) do
						if type == tag.skillType then
							desc = "Skill type: "..(tag.neg and "Not " or "")..self:FormatModName(name)
							break
						end
					end
					if not desc then
						desc = "Skill type: "..(tag.neg and "Not " or "").."?"
					end
				elseif tag.type == "SlotNumber" then
					desc = "When in slot #"..tag.num
				elseif tag.type == "GlobalEffect" then
					desc = self:FormatModName(tag.effectType)
				elseif tag.type == "Limit" then
					desc = "Limited to "..(tag.limitVar and self:FormatModName(tag.limitVar) or self:FormatModBase(row.mod, tag.limit))
				elseif tag.type == "MonsterTag" then
					desc = "Monster Tag: "..(tag.monsterTagList and table.concat(tag.monsterTagList, "/") or tag.monsterTag)
				else
					desc = self:FormatModName(tag.type)
				end
				if desc then
					row.tags = (row.tags and row.tags .. ", " or "") .. desc
				end
			end
		end
	end
end

function CalcBreakdownClass:FormatModName(modName)
	return modName:gsub("([%l%d]:?)(%u)","%1 %2"):gsub("(%l)(%d)","%1 %2")
end

function CalcBreakdownClass:FormatVarNameOrList(var, varList)
	return var and self:FormatModName(var) or table.concat(varList, "/")
end

function CalcBreakdownClass:FormatModBase(mod, base)
	return mod.type == "BASE" and string.format("%+g", math.abs(base)) or math.abs(base).."%"
end

function CalcBreakdownClass:FormatModValue(value, modType)
	if modType == "BASE" then
		return string.format("%+g base", value)
	elseif modType == "INC" then
		if value >= 0 then
			return value.."% increased"
		else
			return -value.."% reduced"
		end
	elseif modType == "MORE" then
		if value >= 0 then
			return value.."% more"
		else
			return -value.."% less"
		end
	elseif modType == "OVERRIDE" then
		return "Override: "..value
	elseif modType == "FLAG" then
		return value and "True" or "False"
	elseif modType == "LIST" then
		if value.mod then
			return "Modifier: "..self:FormatModName(value.mod.name)
		else
			return "?"
		end
	else
		return value		
	end
end

function CalcBreakdownClass:DrawBreakdownTable(viewPort, x, y, section)
	local cursorX, cursorY = GetCursorPos()
	if section.label then
		-- Draw table label if able
		DrawString(x + 2, y, "LEFT", 16, "VAR", "^7"..section.label..":")
		y = y + 16
	end
	local colX = x + 4
	for index, col in ipairs(section.colList) do
		if col.width then
			-- Column is present, draw the separator and label
			col.x = colX
			if index > 1 then
				-- Skip the separator for the first column
				SetDrawColor(0.5, 0.5, 0.5)
				DrawImage(nil, colX - 2, y, 1, section.height - (section.label and 16 or 0) - (section.footer and 12 or 0))
			end
			SetDrawColor(1, 1, 1)
			DrawString(colX, y + 2, "LEFT", 16, "VAR", col.label)
			colX = colX + col.width
		end
	end
	local rowY = y + 20
	for _, row in ipairs(section.rowList) do
		-- Draw row separator
		SetDrawColor(0.5, 0.5, 0.5)
		DrawImage(nil, x + 2, rowY - 1, section.width - 4, 1)
		for _, col in ipairs(section.colList) do
			if col.width and row[col.key] then
				-- This row has an entry for this column, draw it
				local _, alpha = string.gsub(row[col.key], "%a", " ") -- counts letters in the string
				local _, notes = string.gsub(row[col.key], " to ", " ") -- counts " to " in the string
				local _, paren = string.gsub(row[col.key], "%b()", " ") -- counts parenthesis in the string
				if (alpha == 0 or notes > 0 or paren > 0) and col.right then
					DrawString(col.x + col.width - 4, rowY + 1, "RIGHT_X", 12, "VAR", "^7"..formatNumSep(tostring(row[col.key])))
				elseif (alpha == 0 or notes > 0 or paren > 0) then
					DrawString(col.x, rowY + 1, "LEFT", 12, "VAR", "^7"..formatNumSep(tostring(row[col.key])))
				else
					DrawString(col.x, rowY + 1, "LEFT", 12, "VAR", "^7"..tostring(row[col.key]))
				end
				local ttFunc = row[col.key.."Tooltip"]
				local ttNode = row[col.key.."Node"]
				if (ttFunc or ttNode) and cursorY >= viewPort.y + 2 and cursorY < viewPort.y + viewPort.height - 2 and cursorX >= col.x and cursorY >= rowY and cursorX < col.x + col.width and cursorY < rowY + 14 then
					-- Mouse is over the cell, draw highlighting lines and show the tooltip/node location
					SetDrawLayer(nil, 15)
					SetDrawColor(0, 1, 0)
					DrawImage(nil, col.x - 2, rowY - 1, col.width, 1)
					DrawImage(nil, col.x - 2, rowY + 13, col.width, 1)
					if ttFunc then
						self.tooltip:Clear()
						ttFunc(self.tooltip)
						self.tooltip:Draw(col.x, rowY, col.width, 12, viewPort)
					elseif ttNode and ttNode.x and ttNode.y then -- The source "node" from cluster jewels don't know their location because it's the abstract node in tree.lua rather than the generated node from the cluster jewel.
						local viewerX = col.x + col.width + 5
						if viewPort.x + viewPort.width < viewerX + 304 then
							viewerX = col.x - 309
						end
						local viewerY = m_min(rowY, viewPort.y + viewPort.height - 304)
						SetDrawColor(1, 1, 1)
						DrawImage(nil, viewerX, viewerY, 304, 304)
						local viewer = self.nodeViewer
						viewer.zoom = 5
						local scale = self.calcsTab.build.spec.tree.size / 1500
						viewer.zoomX = -ttNode.x / scale
						viewer.zoomY = -ttNode.y / scale
						SetViewport(viewerX + 2, viewerY + 2, 300, 300)
						viewer:Draw(self.calcsTab.build, { x = 0, y = 0, width = 300, height = 300 }, { })
						SetDrawLayer(nil, 30)
						SetDrawColor(1, 0, 0)
						DrawImage(viewer.highlightRing, 135, 135, 30, 30)
						SetViewport()
					end
					SetDrawLayer(nil, 10)
				end
			end
		end
		rowY = rowY + 14
	end
	if section.footer then
		-- Draw table footer if able
		DrawString(x + 2, rowY, "LEFT", 12, "VAR", "^7"..section.footer)
	end
end

function CalcBreakdownClass:DrawRadiusVisual(x, y, width, height, radius)
	SetDrawColor(0.75, 0.75, 0.75)
	DrawImage(self.rangeGuide, x, y, width, height)
	--SetDrawColor(0, 0, 0)
	--DrawImage(nil, x, y, width, height)
	--[[SetDrawColor(0.5, 0.5, 0.75)
	for r = 10, 130, 20 do
		main:RenderRing(x, y, width, height, 0, 0, r, 3)
	end
	SetDrawColor(1, 1, 1)
	for r = 20, 120, 20 do
		main:RenderRing(x, y, width, height, 0, 0, r, 3)
	end
	main:RenderCircle(x, y, width, height, 0, 0, 2)]]
	SetDrawColor(0.5, 1, 0.5, 0.33)
	main:RenderCircle(x, y, width, height, 0, 0, radius)
	--[[SetDrawColor(1, 0.5, 0.5, 0.33)
	if not self.foo1 then
		self.foo1, self.foo2 = 0, 0
	end
	if IsKeyDown("LEFT") then
		self.foo1 = self.foo1 - 0.3
	elseif IsKeyDown("RIGHT") then
		self.foo1 = self.foo1 + 0.3
	end
	if IsKeyDown("UP") then
		self.foo2 = self.foo2 + 0.3
	elseif IsKeyDown("DOWN") then
		self.foo2 = self.foo2 - 0.3
	end
	main:RenderCircle(x, y, width, height, self.foo1, self.foo2, 30)]]
	SetDrawColor(1, 1, 1)
	DrawImage(self.uiOverlay, x, y, width, height)
end

function CalcBreakdownClass:Draw(viewPort)
	local sourceData = self.sourceData
	local scrollBar = self.controls.scrollBar
	local width = self.contentWidth
	local height = self.contentHeight
	if self.contentHeight > viewPort.height then
		-- Content won't fit the screen height, so set the scrollbar
		width = self.contentWidth + scrollBar.width
		height = viewPort.height
		scrollBar.height = height - 4
		scrollBar:SetContentDimension(self.contentHeight - 4, viewPort.height - 4)
	else
		scrollBar:SetContentDimension(0, 0)
	end
	self.width = width
	self.height = height
	-- Calculate position based on the source cell
	local x = sourceData.x + sourceData.width + 5
	local y = m_min(sourceData.y, viewPort.y + viewPort.height - height)
	if x + width > viewPort.x + viewPort.width then
		x = m_max(viewPort.x, sourceData.x - 5 - width)
	end
	self.x = x
	self.y = y
	-- Draw background
	SetDrawLayer(nil, 10)
	SetDrawColor(0, 0, 0, 0.9)
	DrawImage(nil, x + 2, y + 2, width - 4, height - 4)
	-- Draw border (this is put in sub layer 11 so it draws over the contents, in case they don't fit the screen)
	SetDrawLayer(nil, 11)
	if self.pinned then
		SetDrawColor(0.25, 1, 0.25)
	else
		SetDrawColor(0.33, 0.66, 0.33)
	end
	DrawImage(nil, x, y, width, 2)
	DrawImage(nil, x, y + height - 2, width, 2)
	DrawImage(nil, x, y, 2, height)
	DrawImage(nil, x + width - 2, y, 2, height)
	SetDrawLayer(nil, 10)
	self:DrawControls(viewPort)
	-- Draw the sections
	y = y - scrollBar.offset
	for i, section in ipairs(self.sectionList) do
		local sectionY = y + section.offset
		if section.type == "TEXT" then
			local lineY = sectionY + 2
			for i, line in ipairs(section.lines) do
				SetDrawColor(1, 1, 1)
				local _, dec = string.gsub(line, "%.%d%d.", " ") -- counts decimals with 2 or more digits
				DrawString(x + 4, lineY, "LEFT", section.textSize, "VAR", formatNumSep(line))
				lineY = lineY + section.textSize
			end
		elseif section.type == "TABLE" then
			self:DrawBreakdownTable(viewPort, x, sectionY, section)
		elseif section.type == "RADIUS" then
			SetDrawColor(1, 1, 1)
			DrawImage(nil, x + 2, sectionY, section.width - 4, section.height)
			self:DrawRadiusVisual(x + 4, sectionY + 2, section.width - 8, section.height - 4, section.radius)
		end
	end
	SetDrawLayer(nil, 0)
end

function CalcBreakdownClass:OnKeyDown(key, doubleClick)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	local mOverControl = self:GetMouseOverControl()
	if mOverControl and mOverControl.OnKeyDown then
		return mOverControl:OnKeyDown(key)
	end
	local mOver = self:IsMouseOver()
	if key:match("BUTTON") then
		if not mOver then
			-- Mouse click outside the control, hide the breakdown
			self.calcsTab:ClearDisplayStat()
			self.shown = false
			return
		end
	end
	return self
end

function CalcBreakdownClass:OnKeyUp(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	if key == "WHEELDOWN" then
		self.controls.scrollBar:Scroll(1)
	elseif key == "WHEELUP" then
		self.controls.scrollBar:Scroll(-1)
	end
	return self
end
