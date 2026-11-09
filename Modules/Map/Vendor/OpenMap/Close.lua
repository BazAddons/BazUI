-- SPDX-License-Identifier: MIT
-- Adapted from OpenMap v0.8.2, Copyright (c) 2026 OpenMap contributors.
-- See Modules/Map/Vendor/OpenMap/LICENSE.txt and NOTICE.md.
--------------------------------------------------------------------------------
-- The closest zoom levels: where Blizzard's art runs out of pixels.
--   minimap    the game's minimap tiles over the painted map (ns.MapMinimap): their own
--              colours, softened and warmed toward the parchment with a hint of the zone's
--              own (ns.MapTones), adding real tree cover, rocks and buildings.
--              A plain blend: it can't brighten past white (an additive one blew out pale
--              zones like Tanaris), and it leaves the map opaque (a multiply, in game,
--              also multiplies the map's opacity and the world shows through).
--              Over the underground cities (Ironforge, Undercity), whose minimap is the surface
--              over them, the game's minimap of the city inside (ns.MapCityMinimap) instead.
--   soft       the zone art blurred a little (S.SetBlur: a five-tap blur of the zones
--              in view) and parchment grain + paper tooth laid over, so stretched art
--              reads as close-up paper, not pixels
--   underground caves and pre-instance areas: Blizzard's own micro maps (ns.MapCaves,
--              frameless: MapCave masks), and every other one as the game's minimap draws
--              it inside (ns.MapCaveMinimap). Zoom right in on one and the surface dims as
--              its map surfaces in at its real place; zoom back out and it sinks.
-- Everything here follows the view: S.SetView from WorldMap.lua on every pan / zoom.
--------------------------------------------------------------------------------

local ns = BazUI.MapRuntime
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")

local d = mod.defaults
d.minimap = true                -- the minimap's detail up close at all (off: the painted map alone, everywhere)
d.minimapMix = 0.45             -- how strong the minimap's detail is up close (0 = none)
d.minimapDeep = 0.85            -- the most it shows at any zoom (reached at the deepest, where the painted map has nothing left)
d.minimapFrom = 20              -- the zoom where it starts to mix in (MINI_FROM: what it can be set to)
d.cityMinimap = true            -- ... over the six major cities' own maps too (off: their own maps alone)
d.soften = true                 -- soften + paper grain at the closest zoom
d.underground = true            -- caves and pre-instance areas
d.gapMinimap = false            -- the minimap in land no zone map covers (experimental: off, that land is left as
                                --  the zone maps' blank parchment, an unfinished map)

local MINI_FADE = { 20, 34 }    -- zoom where the minimap mixes in (at minimapFrom 20: both move with it)
local DEEP_FADE = { 30, 48 }    -- ... and where it takes over, toward minimapDeep
local MINI_FROM = { 1, 60, 1 }  -- minimapFrom's least (the whole world), most, step
mod.MINI_FROM = MINI_FROM
local miniFade, deepFade = { 20, 34 }, { 30, 48 }   -- (the fades as set: kept, not made each view)
local CITY_MINI = 0.5           -- the most the minimap shows over a city's own map
-- ... none over the six major cities' own maps with cityMinimap off
-- BazUI's opacity control also applies above surface cities. Underground
-- cities retain their interior plans rather than exposing surface terrain.
local function CityMost() return mod.db.cityMinimap == false and 0 or (mod.db.cityMinimapMax or CITY_MINI) end
local GAP_FADE, GAP_MIX = { 4, 8 }, 0.6   -- ... and in the gaps between zones: where, and how strongly
local GAP_MAX = 220             -- tiles at most (it starts further out, so more are in view)
local SOFT_FADE = { 8, 18 }    -- ... the softening and grain
local UNDER_START, UNDER_FULL = 4, 1.8      -- view width / cave width where a cave starts / finishes surfacing
local UNDER_ZOOM = { 28, 40 }   -- ... and the zoom it waits for (a big one would rise over its whole zone)
-- (not waiting: a landmark you look at from further out, Blackrock Mountain's inside)
local UNDER_ZOOM_OF = { [33] = false }
-- (and a mountain's deeper floors never surface by themselves: they lie under its main one,
-- Blackrock Caverns and the way down to the Depths under Blackrock Mountain)
local UNDER_SKIP = { [34] = true, [35] = true }
local TILE = 1600 / 3           -- yards per minimap tile
-- the overlay: painted * (1 - mix) + mix * tint * mini. The minimap keeps its own colours,
-- softened (MINI_DESAT) and warmed toward the map's parchment (PAPER), with only a hint of
-- the zone's own colour (TONE_SHARE), so it sits in the painted map's palette without
-- being recoloured
local MINI_DESAT = 0.35
local PAPER = { 1, 0.93, 0.80 }
local TONE_SHARE = 0.25
local DEFAULT_TONE = { 0.56, 0.45, 0.17 }    -- (the zone art's average, where a zone has no tone)

-- a tile's tint from a zone colour: the parchment warmth, a quarter of the way to the zone's
-- colour brought up to full brightness
local function Tint(tone)
	local top = math.max(tone[1], tone[2], tone[3], 1e-3)
	local r, g, b = tone[1] / top, tone[2] / top, tone[3] / top
	return PAPER[1] + (r - PAPER[1]) * TONE_SHARE, PAPER[2] + (g - PAPER[2]) * TONE_SHARE, PAPER[3] + (b - PAPER[3]) * TONE_SHARE
end

local function TileTone(u, v)
	local chain = S.ChainAt(u, v)
	return Tint(ns.MapTones and ns.MapTones[chain[#chain]] or DEFAULT_TONE)
end
local GRAIN = ns.Media.tex .. "MapGrain"
local TOOTH = ns.Media.tex .. "MapTooth"
-- each continent's game maps (its minimap tiles and caves) and each game map's continent (whose land its
-- minimap is drawn through): WoW Forever's two, or a client's own (ns.MapWorld.minimap, world.py)
local CONT_OF, CONT_MAP = { [1415] = { 0 }, [1414] = { 1 } }, { [0] = 1415, [1] = 1414 }
if ns.MapWorld and ns.MapWorld.minimap then
	CONT_OF, CONT_MAP = ns.MapWorld.minimap, {}
	local ids = {}
	for c in pairs(CONT_OF) do ids[#ids + 1] = c end
	table.sort(ids)                 -- (a game map two continents share: the first's land, the Eastern Kingdoms')
	for _, c in ipairs(ids) do
		for _, g in ipairs(CONT_OF[c]) do CONT_MAP[g] = CONT_MAP[g] or c end
	end
end

local function Smooth(x, r)
	local t = math.max(0, math.min(1, (x - r[1]) / (r[2] - r[1])))
	return t * t * (3 - 2 * t)
end

-- the game maps (continent 0 / 1 ...) of the continent the view's centre is on: looked up again only once
-- the centre has moved a little (the game's lookup makes tables, and this runs every frame of a pan or zoom)
local lastCU, lastCV, lastCont
local function ContinentAt(u, v)
	if lastCU and math.abs(u - lastCU) < 0.002 and math.abs(v - lastCV) < 0.002 then return lastCont end
	lastCU, lastCV, lastCont = u, v, nil
	for _, id in ipairs(S.ChainAt(u, v)) do
		if CONT_OF[id] then lastCont = CONT_OF[id] break end
	end
	return lastCont
end

-- every game map (continent 0 / 1 ...) whose continent's map the view overlaps (one list, reused)
local contsInView = {}
local function ContinentsInView(u, v, hu, hv)
	local out = contsInView
	wipe(out)
	for mapID, conts in pairs(CONT_OF) do
		local l, r, t, b = S.Rect(mapID)
		if l and r > u - hu and l < u + hu and b > v - hv and t < v + hv then
			for _, cont in ipairs(conts) do
				if not tContains(out, cont) then out[#out + 1] = cont end
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Minimap tiles
--------------------------------------------------------------------------------

local tiles, pool = {}, {}      -- cont * 4096 + index -> { texture }
local TileKey = function(cont, tx, ty) return cont * 4096 + tx * 64 + ty end   -- (a number: no string a tile a frame)
local wantedTiles, wantedGap = {}, {}   -- (reused each update)

-- a tile, through its continent's land (S.LandMask): the minimap's sea is left out
local function Tile(layer, fid, cont)
	local t = tremove(pool)
	if not t then
		t = { layer:CreateTexture(nil, "ARTWORK") }
		t[1]:SetDesaturation(MINI_DESAT)
	end
	local mask = CONT_MAP[cont] and S.LandMask and S.LandMask(layer, CONT_MAP[cont])
	if t.mask ~= mask then
		if t.mask then t[1]:RemoveMaskTexture(t.mask) end
		if mask then t[1]:AddMaskTexture(mask) end
		t.mask = mask
	end
	t[1]:SetTexture(fid, nil, nil, "LINEAR")
	return t
end

local function DropTile(key)
	local t = tiles[key]
	for _, tex in ipairs(t) do tex:Hide(); S.UnplaceWorld(tex) end
	tiles[key] = nil
	pool[#pool + 1] = t
end

-- The smaller copies of the minimap (ns.MapMinimapLOD, tools/map-preview/minimaplod.py): its detail
-- from further out than its own tiles can be drawn (at most 64 of them; a continent is over a
-- thousand). Each copy is cut into pieces of `per` tiles a side, tinted as the tiles are. Drawn
-- coarse under fine under the game's own tiles, their strengths set so the three add up to `mix`:
-- the finer takes over as fewer tiles are in view
local LOD = ns.Media.tex .. "MapMiniLOD\\"
local NATIVE_FROM = { 64, 36 }  -- tiles in view where the game's own tiles start / finish taking over
local FINE_FROM = { 40, 24 }    -- tiles across the view where the finer copy starts / finishes taking over
local lodPieces, lodPool, wantedLOD = {}, {}, {}   -- key -> texture; free textures; (reused each update)
local lodSets = {}              -- (continent * 2 + level) -> { [col * 64 + row] = true }

local function LODSet(cont, level, keys)
	local k = cont * 2 + level
	if not lodSets[k] then
		local set = {}
		for _, key in ipairs(keys) do set[key] = true end
		lodSets[k] = set
	end
	return lodSets[k]
end

local function LODPiece(layer, cont, sub)
	local t = tremove(lodPool) or layer:CreateTexture(nil, "ARTWORK")
	t:SetDrawLayer("ARTWORK", sub)
	t:SetDesaturation(MINI_DESAT)
	local mask = CONT_MAP[cont] and S.LandMask and S.LandMask(layer, CONT_MAP[cont])
	if t.omMask ~= mask then
		if t.omMask then t:RemoveMaskTexture(t.omMask) end
		if mask then t:AddMaskTexture(mask) end
		t.omMask = mask
	end
	return t
end

-- one copy's pieces over the tiles tx0 .. tx1, ty0 .. ty1, at `alpha`
local function ShowLOD(layer, cont, level, per, keys, tx0, tx1, ty0, ty1, alpha)
	local set = LODSet(cont, level, keys)
	for col = math.floor(tx0 / per), math.floor(tx1 / per) do
		for row = math.floor(ty0 / per), math.floor(ty1 / per) do
			if set[col * 64 + row] then
				local key = ((cont * 2 + level) * 64 + col) * 64 + row
				wantedLOD[key] = true
				local t = lodPieces[key]
				if not t then
					local u0, v0 = S.FromYards(cont, (32 - row * per) * TILE, (32 - col * per) * TILE)
					local u1, v1 = S.FromYards(cont, (32 - (row + 1) * per) * TILE, (32 - (col + 1) * per) * TILE)
					if u0 and u1 then           -- (none for a piece off the stitched world: Outland's, on 530)
						t = LODPiece(layer, cont, -level)
						t:SetTexture(LOD .. cont .. "_" .. per .. "_" .. col .. "_" .. row, nil, nil, "LINEAR")
						lodPieces[key] = t
						S.PlaceWorld(t, math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1))
						t:Show()
					end
				end
				if t then t:SetAlpha(alpha) end
			end
		end
	end
end

local function UpdateMinimap(layer, conts, u, v, hu, hv, mix)
	local wanted = wantedTiles
	wipe(wanted)
	wipe(wantedLOD)
	for _, cont in ipairs(conts) do
		local list = ns.MapMinimap and ns.MapMinimap[cont]
		local xa, ya, xb, yb
		if list and mix > 0.01 then
			xa, ya = S.ToYards(cont, u - hu, v - hv)
			xb, yb = S.ToYards(cont, u + hu, v + hv)
		end
		if xa and xb then
			local tx0, tx1 = math.floor(32 - math.max(ya, yb) / TILE), math.floor(32 - math.min(ya, yb) / TILE)
			local ty0, ty1 = math.floor(32 - math.max(xa, xb) / TILE), math.floor(32 - math.min(xa, xb) / TILE)
			local count, across = (tx1 - tx0 + 1) * (ty1 - ty0 + 1), math.max(tx1 - tx0 + 1, ty1 - ty0 + 1)
			-- how much each shows: the game's tiles, the finer copy, the coarser
			local lods = ns.MapMinimapLOD and ns.MapMinimapLOD[cont]
			local wn = count <= 64 and (lods and Smooth(count, NATIVE_FROM) or 1) or 0
			local fine = Smooth(across, FINE_FROM)
			local a3 = mix * wn
			local a2 = a3 < 1 and mix * (1 - wn) * fine / (1 - a3) or 0
			local a1 = mix * (1 - wn) * (1 - fine) / math.max(1e-3, (1 - a2) * (1 - a3))
			if lods then
				for level, lv in ipairs(lods) do               -- (finest first)
					local a = level == 1 and a2 or a1
					if a > 0.005 then ShowLOD(layer, cont, level, lv[1], lv[2], tx0, tx1, ty0, ty1, math.min(1, a)) end
				end
			end
			if count <= 64 and a3 > 0.005 then
				for tx = tx0, tx1 do
					for ty = ty0, ty1 do
						local fid = list[tx * 64 + ty]
						local u0, v0, u1, v1
						if fid and not tiles[TileKey(cont, tx, ty)] then
							u0, v0 = S.FromYards(cont, (32 - ty) * TILE, (32 - tx) * TILE)
							u1, v1 = S.FromYards(cont, (31 - ty) * TILE, (31 - tx) * TILE)
							if not (u0 and u1) then fid = nil end     -- (a tile off the stitched world)
						end
						if fid then
							local key = TileKey(cont, tx, ty)
							wanted[key] = true
							local t = tiles[key]
							if not t then
								t = Tile(layer, fid, cont)
								tiles[key] = t
								t[1]:SetVertexColor(TileTone((u0 + u1) / 2, (v0 + v1) / 2))
								for _, tex in ipairs(t) do
									S.PlaceWorld(tex, math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1))
									tex:Show()
								end
							end
							t[1]:SetAlpha(a3)
						end
					end
				end
			end
		end
	end
	for key in pairs(tiles) do
		if not wanted[key] then DropTile(key) end
	end
	for key, t in pairs(lodPieces) do
		if not wantedLOD[key] then
			t:Hide(); S.UnplaceWorld(t)
			lodPieces[key] = nil
			lodPool[#lodPool + 1] = t
		end
	end
end

--------------------------------------------------------------------------------
-- The minimap in the gaps (experimental): land no zone map covers (west of Searing Gorge,
-- Mount Hyjal ...) gets the game's minimap of it, from further out than the close-up
-- overlay. Drawn under every zone, through a soft mask of the gaps (MapGapMask), so it
-- fades out at their edges; void tiles past the world's edge are left out (gapfill.py);
-- tinted with the nearest zone's colour.
--------------------------------------------------------------------------------

local gapTiles, gapPools = {}, {}   -- key -> texture; continent -> its free textures (each masked by its land)
local gapSets                   -- continent mapID -> { [x * 64 + y] = true }: the tiles touching a gap

local function GapSet(mapID)
	gapSets = gapSets or {}
	if gapSets[mapID] == nil then
		local set = {}
		for _, key in ipairs(ns.MapGaps and ns.MapGaps.minimap and ns.MapGaps.minimap[mapID] or {}) do set[key] = true end
		gapSets[mapID] = set
	end
	return gapSets[mapID]
end

-- the nearest zone's colour, looking a little way round a point in a gap
local GAP_REACH = { 0, 0.004, 0.009, 0.016 }
local function GapTone(u, v)
	for _, reach in ipairs(GAP_REACH) do
		for k = 0, reach > 0 and 7 or 0 do
			local a = k * math.pi / 4
			local chain = S.ChainAt(u + math.cos(a) * reach, v + math.sin(a) * reach * 1.5)
			local tone = ns.MapTones and ns.MapTones[chain[#chain]]
			if tone then return tone end
		end
	end
	return DEFAULT_TONE
end

local function UpdateGapMinimap(conts, u, v, hu, hv, alpha)
	local wanted, n = wantedGap, 0
	wipe(wanted)
	local layer = S.GapLayer and S.GapLayer()
	for _, cont in ipairs(conts) do
		local list = ns.MapMinimap and ns.MapMinimap[cont]
		local mapID = CONT_MAP[cont]
		local landMask = mapID and ns.MapGaps and S.GapMask and S.GapMask(mapID)   -- (a client with gaps only)
		local xa, ya, xb, yb
		if list and alpha > 0.01 and layer and landMask and ns.MapGaps then
			xa, ya = S.ToYards(cont, u - hu, v - hv)
			xb, yb = S.ToYards(cont, u + hu, v + hv)
		end
		if xa and xb then
			local set = GapSet(mapID)
			local pool = gapPools[cont] or {}
			gapPools[cont] = pool
			local tx0, tx1 = math.floor(32 - math.max(ya, yb) / TILE), math.floor(32 - math.min(ya, yb) / TILE)
			local ty0, ty1 = math.floor(32 - math.max(xa, xb) / TILE), math.floor(32 - math.min(xa, xb) / TILE)
			for tx = tx0, tx1 do
				for ty = ty0, ty1 do
					local fid = list[tx * 64 + ty]
					if fid and n < GAP_MAX and set[tx * 64 + ty] then
						local u0, v0 = S.FromYards(cont, (32 - ty) * TILE, (32 - tx) * TILE)
						local u1, v1 = S.FromYards(cont, (31 - ty) * TILE, (31 - tx) * TILE)
						local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
						do
							n = n + 1
							local key = TileKey(cont, tx, ty)
							wanted[key] = true
							local tex = gapTiles[key]
							if not tex then
								tex = tremove(pool)
								if not tex then
									tex = layer:CreateTexture(nil, "ARTWORK", nil, 5)
									tex:SetDesaturation(MINI_DESAT)
									tex:AddMaskTexture(landMask)
									tex.cont = cont
								end
								tex:SetTexture(fid, nil, nil, "LINEAR")
								tex:SetVertexColor(Tint(GapTone(cu, cv)))
								S.PlaceWorld(tex, math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1))
								tex:Show()
								gapTiles[key] = tex
							end
							tex:SetAlpha(alpha)
						end
					end
				end
			end
		end
	end
	for key, tex in pairs(gapTiles) do
		if not wanted[key] then
			tex:Hide()
			S.UnplaceWorld(tex)
			gapTiles[key] = nil
			local pool = gapPools[tex.cont] or {}
			gapPools[tex.cont] = pool
			pool[#pool + 1] = tex
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Paper grain: two octaves each of mottling and tooth, laid on the map (they move
-- with it) and crossfaded so the grain always looks the same size on screen
--------------------------------------------------------------------------------

local grain
-- (laid over a box well past the view, as the sea's: the grain is fixed on the world, so a pan
-- lays it again only near the box's edge; a zoom or a change of strength, every time)
local GRAIN_BOX = 1.8           -- the box's half extents, of the view's
local grainBox = {}             -- { u0, v0, u1, v1, hu =, amount = } as last laid

local function UpdateGrain(layer, u, v, hu, hv, amount)
	if not grain then
		grain = {}
		for i, spec in ipairs({ { GRAIN, 1 }, { GRAIN, 2 }, { TOOTH, 1 }, { TOOTH, 2 } }) do
			local tex = layer:CreateTexture(nil, "OVERLAY", nil, i)
			tex:SetTexture(spec[1], "REPEAT", "REPEAT")
			grain[i] = { tex = tex, octave = spec[2], tooth = spec[1] == TOOTH }
		end
	end
	local gb = grainBox
	if amount <= 0.01 then
		if gb.amount ~= 0 then
			for _, g in ipairs(grain) do g.tex:Hide() end
			gb.amount = 0
		end
		return
	end
	if gb.hu == hu and gb.amount == amount and u - hu * 1.2 > gb[1] and u + hu * 1.2 < gb[3]
		and v - hv * 1.2 > gb[2] and v + hv * 1.2 < gb[4] then return end
	local W, H = S.Size()
	local u0, u1, v0, v1 = u - hu * GRAIN_BOX, u + hu * GRAIN_BOX, v - hv * GRAIN_BOX, v + hv * GRAIN_BOX
	gb[1], gb[2], gb[3], gb[4], gb.hu, gb.amount = u0, v0, u1, v1, hu, amount
	local want = math.log(hu * 2 * W * 0.35) / math.log(2)      -- a mottle tile ~ a third of the view
	local n = math.floor(want)
	local f = want - n
	for _, g in ipairs(grain) do
		local size = 2 ^ (n + g.octave - 1) / (g.tooth and 6 or 1)          -- world units
		local a = (g.octave == 1 and (1 - f) or f) * amount * (g.tooth and 0.9 or 0.7)
		g.tex:SetTexCoord(u0 * W / size, u1 * W / size, v0 * H / size, v1 * H / size)
		S.PlaceWorld(g.tex, u0, v0, u1, v1)
		g.tex:SetAlpha(a)
		g.tex:SetShown(a > 0.004)   -- (an octave crossfaded out still costs the whole view: hidden)
	end
end

--------------------------------------------------------------------------------
-- Underground: caves and pre-instance areas. Blizzard's own cave maps (ns.MapCaves: its micro maps,
-- frameless through MapCave masks), and every other cave and underground area as the game's minimap
-- draws it inside (ns.MapCaveMinimap, tools/map-caves/minimap.py: its WMOs' minimap pictures, each a
-- square turned as the cave lies). Blizzard's are keyed by their map ID, the minimap's by minus
-- their place in its list.
--------------------------------------------------------------------------------

local caves = {}                -- key -> { frame }, or false
local rects = {}                -- key -> { u0, v0, u1, v1 } (normalized)
local EMPTY = {}
local dim

local function CaveRect(c)
	-- the art covers its world box (UiMin / UiMax are almost always 0..1)
	local u0, v0 = S.FromYards(c[2], c[5], c[6])       -- north-west: max X, max Y
	local u1, v1 = S.FromYards(c[2], c[3], c[4])
	if not u0 or not u1 then return end
	return math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1)
end

-- a minimap cave's box: { continent, minX, minY, maxX, maxY (yards), pictures }
local function MiniRect(c)
	local u0, v0 = S.FromYards(c[1], c[4], c[5])
	local u1, v1 = S.FromYards(c[1], c[2], c[3])
	if not u0 or not u1 then return end
	return math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1)
end

-- any cave's box on the world, worked out once
local function RectOf(key)
	local r = rects[key]
	if r then return r end
	local u0, v0, u1, v1
	if key > 0 then
		u0, v0, u1, v1 = CaveRect(ns.MapCaves[key])
	else
		u0, v0, u1, v1 = MiniRect(ns.MapCaveMinimap[-key])
	end
	if not u0 then return end
	r = { u0, v0, u1, v1 }
	rects[key] = r
	return r
end

local function Cave(layer, id, c)
	local u0, v0, u1, v1 = CaveRect(c)
	if not u0 then return false end
	local frame = CreateFrame("Frame", nil, layer)
	frame:SetAllPoints(layer)
	frame:SetFrameLevel(layer:GetFrameLevel() + 1)
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(S.CaveMasks .. id, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	S.PlaceWorld(mask, u0, v0, u1, v1)
	local tw, th = (u1 - u0) / (1002 / 256), (v1 - v0) / (668 / 256)   -- one 256 px tile in world units
	for n, fid in ipairs(c[11]) do
		local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
		local pw, ph = math.min(256, 1002 - col * 256), math.min(256, 668 - row * 256)
		local tex = frame:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(fid, nil, nil, "TRILINEAR")
		tex:SetTexCoord(0, pw / 256, 0, ph / 256)
		local x0, y0 = u0 + col * tw, v0 + row * th
		S.PlaceWorld(tex, x0, y0, x0 + tw * pw / 256, y0 + th * ph / 256)
		tex:AddMaskTexture(mask)
	end
	return { frame = frame }
end

-- normalized world units a yard on a continent: east-west (u), north-south (v)
local perYard = {}
local function PerYard(cont)
	local k = perYard[cont]
	if not k then
		local u0, v0 = S.FromYards(cont, 0, 0)
		local u1 = S.FromYards(cont, 0, 1000)
		local _, v1 = S.FromYards(cont, 1000, 0)
		if not (u0 and u1 and v1) then return end
		k = { math.abs(u1 - u0) / 1000, math.abs(v1 - v0) / 1000 }
		perYard[cont] = k
	end
	return k[1], k[2]
end

-- the game's minimap of a place inside (a cave, an underground city): its pictures (file, centre X, Y,
-- side in yards, rotation, u1, v0), each a square around the block's picture (its texcoords past the
-- picture: clamped to nothing) turned about its centre; lowest floor first, under the ones above it.
-- On `frame`, in its draw layer `layer`, toned r, g, b; returns the textures
local function Pictures(frame, c, layer, r, g, b)
	local ku, kv = PerYard(c[1])
	local out = {}
	if not ku then return out end
	local p = c[6]
	local n = #p / 7
	for i = 1, n do
		local j = (i - 1) * 7
		local u, v = S.FromYards(c[1], p[j + 2], p[j + 3])
		if u then
			local hu, hv = p[j + 4] / 2 * ku, p[j + 4] / 2 * kv
			local tex = frame:CreateTexture(nil, layer, nil, math.min(7, math.floor((i - 1) * 16 / n) - 8))
			tex:SetTexture(p[j + 1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
			tex:SetTexCoord(0, p[j + 6], p[j + 7], 1)
			tex:SetRotation(p[j + 5])
			tex:SetDesaturation(MINI_DESAT)
			tex:SetVertexColor(r, g, b)
			tex.omWorld = { u - hu, v - hv, u + hu, v + hv }
			S.PlaceWorld(tex, u - hu, v - hv, u + hu, v + hv)
			out[#out + 1] = tex
		end
	end
	return out
end

-- a cave from the game's minimap, toned as the minimap is up close
local function MiniCave(layer, c)
	if not PerYard(c[1]) then return false end
	local frame = CreateFrame("Frame", nil, layer)
	frame:SetAllPoints(layer)
	frame:SetFrameLevel(layer:GetFrameLevel() + 1)
	Pictures(frame, c, "ARTWORK", PAPER[1], PAPER[2], PAPER[3])
	return { frame = frame }
end

local function CaveFrame(layer, key)
	local cave = caves[key]
	if cave == nil then
		if key > 0 then cave = Cave(layer, key, ns.MapCaves[key]) else cave = MiniCave(layer, ns.MapCaveMinimap[-key]) end
		caves[key] = cave
	end
	return cave
end

-- one floor per place: a cave or dungeon entrance with several floors in one spot (Tiragarde
-- Keep ...) shows its first
local primary
local function Primary(id, c)
	if not primary then
		primary = {}
		for k, cc in pairs(ns.MapCaves or EMPTY) do
			if not UNDER_SKIP[k] and (not primary[cc[1]] or k < primary[cc[1]]) then primary[cc[1]] = k end
		end
	end
	return primary[c[1]] == id
end

-- Every cave in view surfaces by how much of the view it fills (UNDER_START .. UNDER_FULL of its
-- longer side) once the zoom is deep enough (UNDER_ZOOM), and stays while it's on screen. The surface
-- above dims and softens for the one you're centred on only, so panning about doesn't darken the
-- whole map.
local underShown = {}           -- (reused each update)
local UNDER_RANGE = { UNDER_FULL, UNDER_START }
local FOCUS_RANGE = { 0.35, 0.8 }
local function Surface(shown, key, r, u, v, hu, hv, steps, focus)
	if not (r[3] > u - hu and r[1] < u + hu and r[4] > v - hv and r[2] < v + hv) then return focus end
	local fill = math.min((2 * hu) / (r[3] - r[1]), (2 * hv) / (r[4] - r[2]))   -- view / cave, its longer way
	local tz = 1 - Smooth(fill, UNDER_RANGE)
	local wait = UNDER_ZOOM_OF[key]
	if wait == nil then wait = UNDER_ZOOM end
	if wait then tz = tz * Smooth(steps, wait) end
	if tz <= 0.01 then return focus end
	-- (not one under land still unexplored, while that's hidden)
	if S.HiddenAt and S.HiddenAt((r[1] + r[3]) / 2, (r[2] + r[4]) / 2) then return focus end
	shown[key] = tz
	local off = math.max(math.abs((r[1] + r[3]) / 2 - u) / hu, math.abs((r[2] + r[4]) / 2 - v) / hv)
	return math.max(focus, tz * (1 - Smooth(off, FOCUS_RANGE)))
end

local function UpdateUnderground(layer, conts, u, v, hu, hv, steps)
	local shown, focus = underShown, 0
	wipe(shown)
	if mod.db.underground and conts then
		for id, c in pairs(ns.MapCaves or EMPTY) do
			if tContains(conts, c[2]) and not UNDER_SKIP[id] and Primary(id, c) then
				local r = RectOf(id)
				if r then focus = Surface(shown, id, r, u, v, hu, hv, steps, focus) end
			end
		end
		for i, c in ipairs(ns.MapCaveMinimap or EMPTY) do
			if tContains(conts, c[1]) then
				local r = RectOf(-i)
				if r then focus = Surface(shown, -i, r, u, v, hu, hv, steps, focus) end
			end
		end
	end
	for key, cave in pairs(caves) do
		if cave and not shown[key] then cave.frame:Hide() end
	end
	for key, t in pairs(shown) do
		local cave = CaveFrame(layer, key)
		if cave then
			cave.frame:Show()
			cave.frame:SetAlpha(t)
		end
	end
	if not dim then
		dim = layer:CreateTexture(nil, "BACKGROUND")
		dim:SetColorTexture(0.05, 0.035, 0.02, 1)
	end
	if focus > 0.01 then
		S.PlaceWorld(dim, u - hu * 1.5, v - hv * 1.5, u + hu * 1.5, v + hv * 1.5)
		dim:SetAlpha(0.45 * focus)
		dim:Show()
	else
		dim:Hide()
	end
	S.SetUnderground(focus)
	return focus
end

-- the cave holding a world position (yards), for the entrance icons: Blizzard's map of it, else the
-- minimap's
function S.CaveAt(cont, x, y)
	for id, c in pairs(ns.MapCaves or EMPTY) do
		if c[2] == cont and x >= c[3] and x <= c[5] and y >= c[4] and y <= c[6] then
			local r = RectOf(id)
			if r then return id, r[1], r[2], r[3], r[4] end
		end
	end
	for i, c in ipairs(ns.MapCaveMinimap or EMPTY) do
		if c[1] == cont and x >= c[2] and x <= c[4] and y >= c[3] and y <= c[5] then
			local r = RectOf(-i)
			if r then return -i, r[1], r[2], r[3], r[4] end
		end
	end
end

-- the smallest cave round a world point (normalized), with a margin: WorldMap.lua lets the zoom go on
-- in over one, until its map fills the view
local CAVE_MARGIN = 0.25         -- (of its size, each side)
local function Nearest(r, u, v, best, area)
	local mu, mv = (r[3] - r[1]) * CAVE_MARGIN, (r[4] - r[2]) * CAVE_MARGIN
	if u < r[1] - mu or u > r[3] + mu or v < r[2] - mv or v > r[4] + mv then return best, area end
	local a = (r[3] - r[1]) * (r[4] - r[2])
	if not area or a < area then return r, a end
	return best, area
end
function S.CaveRectAt(u, v)
	if not mod.db.underground then return end
	local best, area
	for id in pairs(ns.MapCaves or EMPTY) do
		local r = not UNDER_SKIP[id] and RectOf(id)
		if r then best, area = Nearest(r, u, v, best, area) end
	end
	for i in ipairs(ns.MapCaveMinimap or EMPTY) do
		local r = RectOf(-i)
		if r then best, area = Nearest(r, u, v, best, area) end
	end
	if best then return best[1], best[2], best[3], best[4] end
end

--------------------------------------------------------------------------------
-- The underground cities (Ironforge, Undercity): the minimap over them is the surface's (Ironforge's
-- mountain, the ruins over the Undercity), kept off them (S.CityCover). Inside, the game's minimap draws
-- the city's own WMO (ns.MapCityMinimap, tools/map-caves/minimap.py): its pictures go over the city's own
-- map, on its frame (S.UndergroundCity: shown, culled and faded in with it), as the minimap goes over a
-- city in the open: at the minimap's mix, no more than CITY_MINI (none with cityMinimap off). Not a cave:
-- nothing dims round it
--------------------------------------------------------------------------------

local cityPics = {}             -- city mapID -> { its textures, tone =, alpha =, dark = }, or false

local function CityPictures(mapID, c)
	local frame = S.UndergroundCity and S.UndergroundCity(mapID)
	local l, r, t, b = S.Rect(mapID)
	if not frame or not l then return false end
	local tone = { TileTone((l + r) / 2, (t + b) / 2) }    -- (the minimap's own tint there)
	local pics = Pictures(frame, c, "OVERLAY", tone[1], tone[2], tone[3])
	pics.tone = tone
	for _, tex in ipairs(pics) do                -- (shown, and anchored, once there's some of it)
		tex:Hide()
		tex:ClearAllPoints()
		S.UnplaceWorld(tex)
	end
	pics.shown = false
	return pics
end

local function UpdateCityMinimap(u, v, hu, hv, mix)
	for mapID, c in pairs(ns.MapCityMinimap or EMPTY) do
		local pics = cityPics[mapID]
		local frame, hidden, dark = S.UndergroundCity(mapID)
		local l, r, t, b = S.Rect(mapID)
		-- (in view, and its map come in: at alpha 0 they'd still cost their size to draw)
		local near = frame and l and r > u - hu and l < u + hu and b > v - hv and t < v + hv and (frame:GetAlpha() or 0) > 0.01
		if pics == nil and near and mix > 0.004 then
			pics = CityPictures(mapID, c)
			cityPics[mapID] = pics
		end
		if pics then
			local a = (near and not hidden) and math.floor(math.min(mix, CityMost()) * 50 + 0.5) / 50 or 0
			if pics.alpha ~= a then
				pics.alpha = a
				-- (hidden, they let go of their anchors: the game lays out again on every frame of a pan
				-- whatever hangs from the map, shown or not)
				local show = a > 0
				for _, tex in ipairs(pics) do
					tex:SetAlpha(a)
					if show ~= pics.shown then
						if show then
							S.PlaceWorld(tex, tex.omWorld[1], tex.omWorld[2], tex.omWorld[3], tex.omWorld[4])
						else
							tex:ClearAllPoints()
							S.UnplaceWorld(tex)
						end
						tex:SetShown(show)
					end
				end
				pics.shown = show
			end
			if pics.dark ~= dark then      -- (an unfound city darkened as its map is)
				pics.dark = dark
				local tone = pics.tone
				for _, tex in ipairs(pics) do
					tex:SetVertexColor(tone[1] * (dark and dark[1] or 1), tone[2] * (dark and dark[2] or 1), tone[3] * (dark and dark[3] or 1))
					tex:SetDesaturation(dark and math.max(MINI_DESAT, dark[4]) or MINI_DESAT)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------

-- each part runs on its own: one failing (a client difference) mustn't take the others
-- with it. Its error is reported once, and /openmap status lists it.
local failed = {}
S.closeFailed = failed
local stepMs = {}               -- each step's time (ms, smoothed) and its worst, for /openmap status
S.closeSteps = stepMs
local function Try(name, fn, ...)
	local start = debugprofilestop and debugprofilestop()
	local ok, a, b = pcall(fn, ...)
	if start then
		local ms = debugprofilestop() - start
		local s = stepMs[name] or { ms = ms, worst = 0 }
		s.ms, s.worst = s.ms * 0.9 + ms * 0.1, math.max(s.worst, ms)
		stepMs[name] = s
	end
	if ok then return a, b end
	if not failed[name] then
		failed[name] = tostring(a)
		geterrorhandler()(("BazUI Map %s: %s"):format(name, tostring(a)))
	end
end

-- the view: centre (normalized), half extents (normalized), zoom (by the area in view: WorldMap.lua's
-- DetailK), and `steps`: the plain zoom, from the whole world fitting, as far as the wheel has gone.
-- The minimap's fades go by that: the same wheel turns in a small window or full screen (by the
-- area, the full screen's wide view took it in later)
-- the blur rests while the map moves: its four copies of every zone in view are laid out again
-- on every frame of a zoom or pan (about 60 ms a zoom frame and 8 ms a pan frame at 16x,
-- /openmap bench); back `after` seconds once it stops. A lone view update (the map opening, a
-- setting changed) applies it at once: it rests from the second update in a row (`gap` apart at most).
-- It comes back `step` zones a frame: all at once, it was one long frame each time the map stopped,
-- which the next wheel notch, a moment later, landed on. `after` is longer than a pause between
-- notches, so zooming in notch by notch keeps it resting; a zoom starting again stops the return
local BlurRest = { frame = CreateFrame("Frame"), args = {}, at = -10, after = 0.35, gap = 0.1, step = 2 }
BlurRest.frame:Hide()
BlurRest.frame:SetScript("OnUpdate", function(self)
	if mod.Zooming and mod.Zooming() then BlurRest.at = GetTime() return end
	if GetTime() - BlurRest.at < BlurRest.after then return end
	local a = BlurRest.args
	local done = Try("blur", S.SetBlur, a[1], a[2], a[3], a[4], a[5], BlurRest.step)
	if done ~= false then self:Hide() end
end)

S.closeView = {}
function S.SetView(u, v, hu, hv, zoom, steps)
	steps = steps or zoom
	local L = S.closeLayers
	if not L then return end
	local cv = S.closeView
	local start = debugprofilestop and debugprofilestop()
	cv.zoom, cv.time, cv.updates = zoom, GetTime(), (cv.updates or 0) + 1
	if S.Moved then S.Moved() end
	local cont = Try("continent", ContinentAt, u, v)
	Try("sea", S.SetSea, u, v, hu, hv)
	Try("culling", S.Cull, u - hu, v - hv, u + hu, v + hv)
	local soft = mod.db.soften and Smooth(zoom, SOFT_FADE) or 0
	cv.soft = soft
	local now = GetTime()
	local moving = (mod.Zooming and mod.Zooming()) or now - BlurRest.at < BlurRest.gap
	BlurRest.at = now
	local blur = soft               -- (the grain still goes by soft: only the blur rests)
	if soft > 0 and moving then
		local a = BlurRest.args
		a[1], a[2], a[3], a[4], a[5] = soft, u - hu, v - hv, u + hu, v + hv
		BlurRest.frame:Show()
		blur = 0
	else
		BlurRest.frame:Hide()       -- (applied now: an older one waiting would undo it)
	end
	Try("blur", S.SetBlur, blur, u - hu, v - hv, u + hu, v + hv)
	local base = mod.db.minimap and mod.db.minimapMix or 0
	local k = (mod.db.minimapFrom or MINI_FADE[1]) / MINI_FADE[1]          -- (sooner or later: the fades scale with it)
	-- (the take-over toward minimapDeep moves later with it, never sooner: it's where the painted
	-- map runs out of detail)
	miniFade[1], miniFade[2] = MINI_FADE[1] * k, MINI_FADE[2] * k
	deepFade[1], deepFade[2] = DEEP_FADE[1] * math.max(1, k), DEEP_FADE[2] * math.max(1, k)
	local most = mod.db.minimapDeep or 1                     -- (the most it ever shows)
	local from = mod.db.minimapFrom or MINI_FADE[1]
	local mix = math.min(base, most) * (from <= MINI_FROM[1] and 1 or Smooth(steps, miniFade))   -- (at the least: from the whole world)
	if base > 0 then mix = mix + (most - mix) * Smooth(steps, deepFade) end
	-- not over an underground city's own map (the minimap there is the surface, not the city: the
	-- game's minimap of the city inside goes over it instead, UpdateCityMinimap)
	local inside = mix
	mix = mix * (1 - (Try("cities", S.CityCover, u, v) or 0))
	-- and over the cities on the surface no more than CITY_MINI (none with cityMinimap off): their own plan leads
	local city = Try("surface cities", S.SurfaceCityCover, u, v)
	local most = CityMost()
	if mix > most then mix = mix + (most - mix) * (city or 0) end
	cv.mix = mix
	if S.MinimapShown then S.MinimapShown(mix > 0.004) end   -- (unexplored land hidden over it: Stitch.lua)
	local conts = Try("continents", ContinentsInView, u, v, hu, hv) or {}
	Try("minimap", UpdateMinimap, L.minimap, conts, u, v, hu, hv, mix)
	Try("underground cities' minimap", UpdateCityMinimap, u, v, hu, hv, inside)
	cv.gapTiles = Try("minimap in the gaps", UpdateGapMinimap, conts, u, v, hu, hv,
		mod.db.minimap and mod.db.gapMinimap and GAP_MIX * Smooth(steps, GAP_FADE) or 0)
	local under = Try("underground", UpdateUnderground, L.under, cont, u, v, hu, hv, steps) or 0
	-- the out-of-focus world above a cave gets heavier grain
	Try("grain", UpdateGrain, L.grain, u, v, hu, hv, math.max(soft, math.min(1.4, under * 1.4)))
	for i, fn in ipairs(S.viewHooks) do Try("view hook " .. i, fn, u, v, hu, hv, zoom) end
	local n = 0
	for _ in pairs(tiles) do n = n + 1 end
	cv.tiles = n
	if start then
		local ms = debugprofilestop() - start
		cv.ms = (cv.ms or ms) * 0.9 + ms * 0.1
		cv.worst = math.max(cv.worst or 0, ms)
	end
end

