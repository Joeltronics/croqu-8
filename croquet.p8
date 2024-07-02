pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- By Joel Geddert
-- License: CC BY-NC-SA 4.0

--
-- Game core consts
--

BALL_R = 2

MOVING_COOLDOWN_FRAMES = 120

ROUGH = 16

-- WIDTH, HEIGHT = 256, 128
WIDTH, HEIGHT = 384 + 2*ROUGH, 192+2*ROUGH

CX = WIDTH \ 2
CY = HEIGHT \ 2

PX = 32
W1X = 64
W2X = 96
W3X = CX - 48
WY = CY - 48

WICKETS = {
	{PX, CY, pole=true},
	{W1X, CY},
	{W2X, CY},
	{W3X, HEIGHT - WY},
	{CX, CY},
	{WIDTH - W3X, HEIGHT - WY},
	{WIDTH - W2X, CY},
	{WIDTH - W1X, CY},
	{WIDTH - PX, CY, pole=true},
	{WIDTH - W1X, CY, reverse=true, hidden=true},
	{WIDTH - W2X, CY, reverse=true, hidden=true},
	{WIDTH - W3X, WY, reverse=true},
	{CX, CY, reverse=true, hidden=true},
	{W3X, WY, reverse=true},
	{W2X, CY, reverse=true, hidden=true},
	{W1X, CY, reverse=true, hidden=true},
	{PX, CY, reverse=true, pole=true, hidden=true},
}

--
-- Physics consts
--

SHOT_V_MAX = 2.5
SHOT_V_MIN = 0.125

DRAG = 1 - 1/128
DRAG_ROUGH = 1 - 1/8
V2_STOP_THRESH = 1/1024

BALL_STOP_RANDOM_MOVEMENT = 0.25

--
-- Graphics Consts
--

STATUS_BAR_HEIGHT = 7

ROUGH_FILLP = 0b0101010110101010
-- ROUGH_COLOR = 0x34
ROUGH_COLOR = 0x35

PALETTES = {
	-- main, dark, light
	{[8]=12, [2]=1, [14]=6}, -- Blue
	{[8]=8, [2]=2, [14]=14}, -- Red
	{[8]=0, [2]=5, [14]=5}, -- Black
	{[8]=10, [2]=9, [14]=6}, -- Yellow

	{[8]=1, [2]=5, [14]=12}, -- Dark blue
	-- {[8]=3, [2]=5, [14]=11}, -- Green

	{[8]=9, [2]=4, [14]=10}, -- Orange
}

SHOT_POWER_COLORS = {1, 12, 11, 10, 9, 8}

--
-- Globals
--

balls = {}

player_idx = 0

camera_x = 64
camera_y = CY

shot_angle = 0
shot_power = 0.25

moving_cooldown = 0

debug_no_draw_tops = false
debug_draw_primitives = false

--
-- Utility functions
--

function round(val)
	return flr(val + 0.5)
end

function line_round(x1, y1, x2, y2, col)
	line(round(x1), round(y1), round(x2), round(y2), col)
end

function clip_num(val, minval, maxval)
	return max(minval, min(maxval, val))
end

function sort_z(items)
	-- Bubblesort items by z value, or y value if z is not found
	for idx1 = 1,#items do
		local any_swapped = false
		for idx2 = 1,#items-1 do
			local item1 = items[idx1]
			local item2 = items[idx2]
			if ((item1.z or item1.y) < (item2.z or item2.y)) then
				items[idx1] = item2
				items[idx2] = item1
				any_swapped = true
			end
		end
		if (not any_swapped) return
	end
end

function shot_power_color()
	return SHOT_POWER_COLORS[clip_num(flr(shot_power * #SHOT_POWER_COLORS) + 1, 1, #SHOT_POWER_COLORS)]
end

--
-- Game
--

function reset_off_screen_balls()

	while true do
		local any_clipped = false

		for ball in all(balls) do
			local x_was, y_was = ball.x, ball.y
			ball.x = clip_num(ball.x, ROUGH, WIDTH-ROUGH-1)
			ball.y = clip_num(ball.y, ROUGH, HEIGHT-ROUGH-1)
			if (ball.x != x_was or ball.y != y_was) any_clipped = true
		end

		if (not any_clipped) return

		-- TODO: re-run ball collisions
	end
end

function next_player()

	reset_off_screen_balls()

	player_idx %= #PALETTES
	player_idx += 1
	if (player_idx > #balls) add_ball()
	shot_angle = 0
	shot_power = 0.25
	moving_cooldown = 0

	local player_ball = balls[player_idx]

	camera_x = player_ball.x
	camera_y = player_ball.y
end

function add_ball()
	local palette = PALETTES[#balls + 1]
	add(balls, {
		x=WICKETS[1][1] + 3,
		y=WICKETS[1][2] + 3,
		vx=0,
		vy=0,
		color=palette[8],
		palette=palette,
		last_wicket_idx=1,
	})
end

function _init()
	balls = {}
	player_idx = 0
	next_player()

	cls()
	poke(0x5F2D, 1)  -- enable keyboard
	poke(0x5f36, 0x40)  -- prevent printing at bottom of screen from triggering scroll
end

function check_wicket(ball)
	-- Note: only checks wickets, not poles
	-- (Poles are handled through collision physics)

	local w = WICKETS[ball.last_wicket_idx + 1]
	if (w.pole) return
	local x, y, xp, yp, wx, wy = ball.x, ball.y, ball.x_prev, ball.y_prev, w[1], w[2]

	local through = false
	if wy - 4 <= y and y <= wy + 4 then
		if x == wx then
			-- In case ball is stopped exactly on wicket
			-- (Could handle this with conditions below, but this is more mistake-proof)
			through = true
		elseif w.reverse then
			if (xp >= wx and x < wx) through = true
		else
			if (xp <= wx and x > wx) through = true
		end
	end
	if (through) ball.last_wicket_idx += 1
end

function _update60()

	local player_ball, op, x = balls[player_idx], btnp(4), btn(5)

	while stat(30) do
		local key = stat(31)
		if (key == '1') debug_draw_primitives = not debug_draw_primitives
		if (key == '2') debug_no_draw_tops = not debug_no_draw_tops
	end

	if op and moving_cooldown <= 0 then
		-- Launch ball

		-- TODO: add slight randomness to angle, depending on power

		local dx, dy = cos(shot_angle), sin(shot_angle)

		local v = SHOT_V_MIN + (SHOT_V_MAX - SHOT_V_MIN) * shot_power * shot_power

		player_ball.vx = v * dx
		player_ball.vy = v * dy
		moving_cooldown = MOVING_COOLDOWN_FRAMES
	end

	if moving_cooldown > 0 then
		-- Process physics

		moving_cooldown -= 1

		-- TODO optimization: keep a list of moving balls, only iterate those

		for ball in all(balls) do
			ball.x_prev = ball.x
			ball.y_prev = ball.y
			ball.x += ball.vx
			ball.y += ball.vy
		end

		-- TODO: collision physics here
		-- TODO: collision physics needs to include pole hit check

		for ball in all(balls) do
			if ball.vx != 0 or ball.vy != 0 then

				local drag = DRAG
				if (ball.x < ROUGH or ball.y < ROUGH or ball.x >= WIDTH-ROUGH or ball.y >= HEIGHT-ROUGH) drag = DRAG_ROUGH

				ball.vx *= drag
				ball.vy *= drag

				local v2 = ball.vx*ball.vx + ball.vy*ball.vy
				if (v2 <= V2_STOP_THRESH) then
					-- Stop ball

					-- Move ball slightly when it stops
					-- TODO: Add ball spin, and make this depend on it
					ball.x = round(ball.x + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
					ball.y = round(ball.y + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)

					ball.vx, ball.vy = 0, 0
				else
					moving_cooldown = MOVING_COOLDOWN_FRAMES
				end
			end
		end

		for ball in all(balls) do
			check_wicket(ball)
		end

		-- TODO: If player's ball isn't moving but another is, make camera follow that one instead
		camera_x = player_ball.x
		camera_y = player_ball.y

		if (moving_cooldown <= 0) next_player()

	else
		if x then
			if (btn(0)) camera_x -= 4  -- left
			if (btn(1)) camera_x += 4  -- right
			if (btn(2)) camera_y -= 4  -- up
			if (btn(3)) camera_y += 4  -- down
		else
			if (btn(0)) shot_angle += 1/256  -- left
			if (btn(1)) shot_angle -= 1/256  -- right
			if (btn(2)) shot_power += 1/64  -- up
			if (btn(3)) shot_power -= 1/64  -- down
		end

		shot_angle = round((shot_angle * 256) % 256) / 256
		shot_power = clip_num(shot_power, 0, 1)
	end

	moving_cooldown = max(moving_cooldown, 0)
	camera_x = clip_num(camera_x, 64, WIDTH-64)
	camera_y = clip_num(camera_y, 64, HEIGHT-64+STATUS_BAR_HEIGHT)

	cpu_update = stat(1)
end

function draw_shot()
	local player_ball = balls[player_idx]
	local x, y = player_ball.x, player_ball.y
	if (not x) return -- HACK: this shouldn't be needed
	local dx, dy = cos(shot_angle), sin(shot_angle)

	-- Draw line

	line_round(x, y, x + 12*dx, y + 12*dy, shot_power_color())

	-- Draw club

	-- TODO: Haven't worked out a good way to draw this as solid without gaps at
	-- some angles, so for now just draw outline

	local w, l, d = 1.5, 10, 4 + 5*shot_power*shot_power

	local c = {
		{ w*dy - d*dx,     -w*dx - d*dy},
		{ w*dy - (d+l)*dx, -w*dx - (d+l)*dy},
		{-w*dy - (d+l)*dx,  w*dx - (d+l)*dy},
		{-w*dy - d*dx,      w*dx - d*dy},
	}

	for idx=1,4 do
		line_round(
			x + c[idx][1],
			y + c[idx][2],
			x + c[(idx%4)+1][1],
			y + c[(idx%4)+1][2],
			4)
	end
end

function draw_shot_power_meter()
	rectfill(125, 63 - 62*shot_power, 126, 63, shot_power_color())
	rect(124, 0, 127, 64, 0)
end

function _draw()

	local player_ball, x, y = balls[player_idx]
	local next_wicket = WICKETS[player_ball.last_wicket_idx + 1]

	camera(camera_x - 64, camera_y - 64)

	--
	-- Field
	--

	for y=0,ceil((HEIGHT-2*ROUGH)/16) do
		for x=0,ceil((WIDTH-2*ROUGH)/16) do
			local fp = 0b0101101001011010
			if (x % 2 == 0 and y % 2 == 0) fp = 0x0000
			if (x % 2 == 1 and y % 2 == 1) fp = 0xFFFF
			fillp(fp)
			local off = ROUGH
			if (ROUGH < 1) off = -8
			rectfill(x*16 + off, y*16 + off, x*16 + 16 + off, y*16 + 16 + off, 0xDF)
		end
	end
	if ROUGH > 0 then
		fillp(ROUGH_FILLP)
		rectfill(0, 0, WIDTH, ROUGH-1, ROUGH_COLOR)
		rectfill(0, HEIGHT - ROUGH, WIDTH, HEIGHT, ROUGH_COLOR)
		rectfill(0, ROUGH, ROUGH, HEIGHT - ROUGH, ROUGH_COLOR)
		rectfill(WIDTH - ROUGH, ROUGH, WIDTH, HEIGHT - ROUGH, ROUGH_COLOR)
	end
	fillp()

	-- Boundary
	if (ROUGH < 1) rect(0, 0, WIDTH - 1, HEIGHT - 1, 7)

	--
	-- Bases & shadows
	--

	-- Draw ball shadows
	-- TODO: Disabled for now, it looks bad with ball palettes that use grey as their dark color
	-- if not debug_draw_primitives then
	-- 	for ball in all(balls) do
	-- 		spr(2, ball.x - 2, ball.y - 4)
	-- 	end
	-- end

	-- Draw wicket & pole bases
	if not debug_draw_primitives then
		palt(0, false)
		palt(3, true)
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					spr(39, w[1]-3, w[2]-7)
				else
					spr(17, w[1]-4, w[2]-9, 1, 2)
				end
			end
		end
		palt()
	end	

	-- Draw arrow on next wicket

	x, y = next_wicket[1], next_wicket[2] - 4
	if next_wicket.pole then
		x -= 9
		if (next_wicket.reverse) x += 11
		y += 1
	elseif next_wicket.reverse then
		x -= 4
	else
		x -= 3
	end
	spr(3, x, y, 1, 1, next_wicket.reverse)

	if (moving_cooldown <= 0) draw_shot()

	--
	-- Balls & wickets - stuff where Z-order matters
	--

	local sprites = {}

	for ball in all(balls) do
		if debug_draw_primitives then
			circ(ball.x, ball.y, BALL_R, ball.color)
			line(ball.x, ball.y, ball.x, ball.y, 0)
		else
			add(sprites, {idx=1, x=ball.x - 3, y=ball.y-3, z=ball.y, pal=ball.palette})
		end
	end
	pal()

	if (not debug_no_draw_tops) and (not debug_draw_primitives) then
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					add(sprites, {idx=23, x=w[1]-3, y=w[2]-7, z=w[2], palt=3})
				else
					-- TODO: is this the right z?
					add(sprites, {idx=18, x=w[1]-4, y=w[2]-9, z=w[2], h=2, palt=3})
				end
			end
		end
	end

	--
	-- Draw sprites, in Z order
	--

	--[[
	TODO optimizations: (Bubblesort is slow, O(n^2))
	- Do not add offscreen sprites to list
	- Sort list of wickets at init, then they're already sorted
	- Sort list each time we add a sprite
	]]

	sort_z(sprites)

	for s in all(sprites) do
		pal(s.pal)
		if (s.palt) then
			palt(0, false)
			palt(s.palt, true)
		else
			palt()
		end
		spr(s.idx, round(s.x), round(s.y), s.w or 1, s.h or 1)
	end
	palt()
	pal()

	if debug_draw_primitives then
		for w in all(WICKETS) do
			if w.pole then
				line(w[1], w[2], w[1], w[2], 8)
			else
				line(w[1], w[2] - 5, w[1], w[2] - 5, 9)
				line(w[1], w[2] + 4, w[1], w[2] + 4, 9)
			end
		end
	end

	--
	-- HUD
	--

	camera()
	rectfill(0, 128 - STATUS_BAR_HEIGHT, 128, 128, 4)

	-- for idx=1,#balls do
	for idx=1,#PALETTES do
		cursor(8 + 12*idx, 129 - STATUS_BAR_HEIGHT, PALETTES[idx][8])
		if idx <= #balls then
			print(balls[idx].last_wicket_idx - 1)
		else
			print(0)
		end
	end

	if (moving_cooldown <= 0) draw_shot_power_meter()

	--
	-- Debug overlays
	--

	-- cursor(1, 1, 8)
	cursor(112, 1, 8)
	-- print('mem:' .. stat(0))
	local cpu = stat(1)
	-- local cpu_draw = cpu - cpu_update
	-- print('cpu:' .. round(cpu * 100) .. '=' .. round(cpu_update * 100) .. '+' .. round(cpu_draw * 100))
	print(round(cpu * 100))

	--
	-- Display palette
	--

	-- pal({[13]=139,[15]=138}, 1)
	pal({[13]=139,[15]=3}, 1)
	-- pal({[13]=3,[15]=138}, 1)
end

__gfx__
00000000000000000000000000000000000000003333777777773333333c33330000000000000000000000000000000000000000000000000000000000000000
0000000000e880000000000000000800000000003333733333373333333833330000000000000000000000000000000000000000000000000000000000000000
000000000e7e88000000000000000880000000003333733333373333333033330000000000000000000000000000000000000000000000000000000000000000
0000000008e888000055550088888888000000003333733333373333333a33330000000000000000000000000000000000000000000000000000000000000000
00000000088882000555555000000880000000003333733555575553333133530000000000000000000000000000000000000000000000000000000000000000
00000000008220000555555000000800000000003333735333373533333935330000000000000000000000000000000000000000000000000000000000000000
00000000000000000055550000000000000000003333753333375333333453330000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000003333733333373333333433330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333777777773333333c33330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733333333333333333333333733333373333333833330000000000000000000000000000000000000000000000000000000000000000
33337355333333553333733333333333333333333333733333373333333033330000000000000000000000000000000000000000000000000000000000000000
33337535333335353333733333333333333333333333733333373333333a33330000000000000000000000000000000000000000000000000000000000000000
333373353333e3353333733333334333333343333333733333373333333133330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733333333533333333333333733333373333333933330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733333333353333333333333733333373333333433330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733333333335333333333333733333373333333433330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733300000000000000003333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33337335333333353333733300000000000000003333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33336335333333353333633300000000000000003333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33336353333333533333633300000000000000003333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33336533333335333333633300000000000000003333333555555553333333530000000000000000000000000000000000000000000000000000000000000000
333363333333e3333333633300000000000000003333335333333533333335330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333300000000000000003333353333335333333353330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333300000000000000003333533333353333333e33330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33337777777733333333733333373333333377777777333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333533333353333333353333335333333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333353333335333333335333333533333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333335555555533333333555555553333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101020201010202010102020101020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020201010202010102020101020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202030302020303020203030202030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202030302020303020203030202030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020201010202010102020101020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020201010202010102020101020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202030302020303020203030202030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202030302020303020203030202030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1314000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
