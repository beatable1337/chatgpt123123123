local ffi = require("ffi")
local pui = require("gamesense/pui")
local http = require("gamesense/http")
local base64 = require("gamesense/base64")
local vector = require("vector")

local plist_set, plist_get = plist.set, plist.get
local getplayer = entity.get_players
local entity_is_enemy = entity.is_enemy

-- Utils
local function get_velocity()
    if not entity.get_local_player() then return end
    local first_velocity, second_velocity = entity.get_prop(entity.get_local_player(), "m_vecVelocity")
    local speed = math.floor(math.sqrt(first_velocity * first_velocity + second_velocity * second_velocity))
    return speed
end

local ground_tick = 1
local function get_state(speed)
    if not entity.is_alive(entity.get_local_player()) then return end
    local flags = entity.get_prop(entity.get_local_player(), "m_fFlags")
    local land = bit.band(flags, bit.lshift(1, 0)) ~= 0
    if land then ground_tick = ground_tick + 1 else ground_tick = 0 end

    if bit.band(flags, 1) == 1 then
        if ground_tick < 10 then if bit.band(flags, 4) == 4 then return 5 else return 4 end end
        if bit.band(flags, 4) == 4 or ui.get(ref.fakeduck) then 
            return 6 -- crouching
        else
            if speed <= 3 then
                return 2 -- standing
            else
                if ui.get(ref.slide[2]) then
                    return 7 -- slowwalk
                else
                    return 3 -- moving
                end
            end
        end
    elseif bit.band(flags, 1) == 0 then
        if bit.band(flags, 4) == 4 then
            return 5 -- air-c
        else
            return 4 -- air
        end
    end
end

ffi.cdef[[
    struct animation_layer_t {
        char pad20[24];
        uint32_t m_nSequence;
        int iOutSequenceNr;
        int iInSequenceNr;
        int iOutSequenceNrAck;
        int iOutReliableState;
        int iInReliableState;
        int iChokedPackets;
        bool m_bIsBreakingLagComp;
        float m_flPrevCycle;
        float m_flWeight;
        char pad20[8];
        float m_flCycle;
        void *m_pOwner;
        char pad_0038[ 4 ]; 
    };

    struct c_animstate { 
        char pad[ 3 ];
        char m_bForceWeaponUpdate; //0x5
        char pad1[ 91 ];
        void* m_pBaseEntity; //0x60
        void* m_pActiveWeapon; //0x64
        void* m_pLastActiveWeapon; //0x68
        float m_flLastClientSideAnimationUpdateTime; //0x6C
        int m_iLastClientSideAnimationUpdateFramecount; //0x70
        float m_flAnimUpdateDelta; //0x74
        float m_flEyeYaw; //0x78
        float m_flPitch; //0x7C
        float m_flGoalFeetYaw; //0x80
        float m_flCurrentFeetYaw; //0x84
        float m_flCurrentTorsoYaw; //0x88
        float m_flUnknownVelocityLean; //0x8C
        float m_flLeanAomunt; //0x90
        char pad2[ 4 ];
        float m_flFeetCycle; //0x98
        float m_flFeetYawRate; //0x9C
        char pad3[ 4 ];
        float m_fDuckAmount; //0xA4
        float m_fLandingDuckAdditiveSomething; //0xA8
        char pad4[ 4 ];
        float m_vOriginX; //0xB0
        float m_vOriginY; //0xB4
        float m_vOriginZ; //0xB8
        float m_vLastOriginX; //0xBC
        float m_vLastOriginY; //0xC0
        float m_vLastOriginZ; //0xC4
        float m_vVelocityX; //0xC8
        float m_vVelocityY; //0xCC
        char pad5[ 4 ];
        float m_flUnknownFloat1; //0xD4
        char pad6[ 8 ];
        float m_flUnknownFloat2; //0xE0
        float m_flUnknownFloat3; //0xE4
        float m_flUnknown; //0xE8
        float m_flSpeed2D; //0xEC
        float m_flUpVelocity; //0xF0
        float m_flSpeedNormalized; //0xF4
        float m_flFeetSpeedForwardsOrSideWays; //0xF8
        float m_flFeetSpeedUnknownForwardOrSideways; //0xFC
        float m_flTimeSinceStartedMoving; //0x100
        float m_flTimeSinceStoppedMoving; //0x104
        bool m_bOnGround; //0x108
        bool m_bInHitGroundAnimation; //0x109
        float m_flTimeSinceInAir; //0x10A
        float m_flLastOriginZ; //0x10E
        float m_flHeadHeightOrOffsetFromHittingGroundAnimation; //0x112
        float m_flStopToFullRunningFraction; //0x116
        char pad7[ 4 ]; //0x11A
        float m_flMagicFraction; //0x11E
        char pad8[ 60 ]; //0x122
        float m_flWorldForce; //0x15E
        char pad9[ 462 ]; //0x162
        float m_flMaxYaw; //0x334
    };

    typedef struct
    {
        float   m_anim_time;     
        float   m_fade_out_time; 
        int     m_flags;         
        int     m_activity;      
        int     m_priority;      
        int     m_order;         
        int     m_sequence;      
        float   m_prev_cycle;    
        float   m_weight;        
        float   m_weight_delta_rate;
        float   m_playback_rate; 
        float   m_cycle;         
        void* m_owner;           
        int     m_bits;          
    } C_AnimationLayer;

    typedef uintptr_t (__thiscall* GetClientEntityHandle_4242425_t)(void*, uintptr_t);

    typedef int(__thiscall* get_clipboard_text_count)(void*);
    typedef void(__thiscall* set_clipboard_text)(void*, const char*, int);
    typedef void(__thiscall* get_clipboard_text)(void*, int, const char*, int);
    typedef bool(__thiscall* console_is_visible)(void*);
]]

local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')
local VGUI_System010 = client.create_interface("vgui2.dll", "VGUI_System010") or print("Error finding VGUI_System010")
local VGUI_System = ffi.cast(ffi.typeof('void***'), VGUI_System010)
local get_clipboard_text_count = ffi.cast("get_clipboard_text_count", VGUI_System[0][7]) or print("get_clipboard_text_count Invalid")
local set_clipboard_text = ffi.cast("set_clipboard_text", VGUI_System[0][9]) or print("set_clipboard_text Invalid")
local get_clipboard_text = ffi.cast("get_clipboard_text", VGUI_System[0][11]) or print("get_clipboard_text Invalid")

local classptr = ffi.typeof('void***')
local rawientitylist = client.create_interface('client.dll', 'VClientEntityList003') or error('VClientEntityList003 wasn\'t found', 2)
local ientitylist = ffi.cast(classptr, rawientitylist) or error('rawientitylist is nil', 2)
local get_client_entity = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][3]) or error('get_client_entity is nil', 2)
local get_client_entity_bind = vtable_bind("client_panorama.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*,int)")
local get_inaccuracy = vtable_thunk(483, "float(__thiscall*)(void*)")

local angle3d_struct = ffi.typeof("struct { float pitch; float yaw; float roll; }")
local vec_struct = ffi.typeof("struct { float x; float y; float z; }")

local cUserCmd = ffi.typeof([[
    struct
    {
        uintptr_t vfptr;
        int command_number;
        int tick_count;
        $ viewangles;
        $ aimdirection;
        float forwardmove;
        float sidemove;
        float upmove;
        int buttons;
        uint8_t impulse;
        int weaponselect;
        int weaponsubtype;
        int random_seed;
        short mousedx;
        short mousedy;
        bool hasbeenpredicted;
        $ headangles;
        $ headoffset;
        bool send_packet;
        int unknown_float2;
        int tickbase_shift;
        int unknown_float3;
        int unknown_float4;
    }
]], angle3d_struct, vec_struct, angle3d_struct, vec_struct)

local client_sig = client.find_signature("client.dll", "\xB9\xCC\xCC\xCC\xCC\x8B\x40\x38\xFF\xD0\x84\xC0\x0F\x85") or error("client.dll!:input not found.")
local get_cUserCmd = ffi.typeof("$* (__thiscall*)(uintptr_t ecx, int nSlot, int sequence_number)", cUserCmd)
local input_vtbl = ffi.typeof([[struct{uintptr_t padding[8]; $ GetUserCmd;}]], get_cUserCmd)
local input = ffi.typeof([[struct{$* vfptr;}*]], input_vtbl)
local get_input = ffi.cast(input, ffi.cast("uintptr_t**", tonumber(ffi.cast("uintptr_t", client_sig)) + 1)[0])

local function clipboard_import()
    local clipboard_text_length = get_clipboard_text_count(VGUI_System)
    if clipboard_text_length > 0 then
        local buffer = ffi.new("char[?]", clipboard_text_length)
        local size = clipboard_text_length * ffi.sizeof("char[?]", clipboard_text_length)
        get_clipboard_text(VGUI_System, 0, buffer, size)
        return ffi.string(buffer, clipboard_text_length - 1)
    end
    return ""
end

local function clipboard_export(string)
    if string then
        set_clipboard_text(VGUI_System, string, string:len())
    end
end

local last_sim_time = 0
local defensive_until = 0
local function is_defensive_active()
    local tickcount = globals.tickcount()
    local sim_time = toticks(entity.get_prop(entity.get_local_player(), "m_flSimulationTime"))
    local sim_diff = sim_time - last_sim_time
    if sim_diff < 0 then
        defensive_until = tickcount + math.abs(sim_diff) - toticks(client.latency())
    end
    last_sim_time = sim_time
    return defensive_until > tickcount
end

local function is_vulnerable()
    for _, v in ipairs(entity.get_players(true)) do
        local flags = (entity.get_esp_data(v)).flags
        if bit.band(flags, bit.lshift(1, 11)) ~= 0 then
            return true
        end
    end
    return false
end

local function contains(tbl, arg)
    for _, value in next, tbl do 
        if value == arg then 
            return true
        end
    end
    return false
end

local animations = {anim_list = {}}
animations.math_clamp = function(value, min, max) return math.min(max, math.max(min, value)) end
animations.math_lerp = function(a, b_, t) return a + (b_ - a) * t end
animations.new = function(name, new, remove, speed) 
    if not animations.anim_list[name] then 
        animations.anim_list[name] = {}
        animations.anim_list[name].color = {0, 0, 0, 0}
    end
end

local function choking(cmd)
    return cmd.allow_send_packet == false or cmd.chokedcommands > 1
end

local function rgba_to_hex(b, c, d, e)
    return string.format('%02x%02x%02x%02x', b, c, d, e)
end

local function hex_to_rgba(hex)
    hex = hex:gsub('#', '')
    return tonumber('0x' .. hex:sub(1, 2)), tonumber('0x' .. hex:sub(3, 4)), tonumber('0x' .. hex:sub(5, 6)), tonumber('0x' .. hex:sub(7, 8)) or 255
end

local function d_lerp(a, b, t)
    return a + (b - a) * t
end

local function d_clamp(x, minval, maxval)
    if x < minval then
        return minval
    elseif x > maxval then
        return maxval
    else
        return x
    end
end

local function animated_text(x, y, speed, color1, color2, flags, text)
    local final_text = ''
    local curtime = globals.curtime()
    for i = 0, #text do
        local wave = math.cos(1 * speed * curtime / 2 + i * 10 / 400)
        local color = rgba_to_hex(
            math.max(0, d_lerp(color1.r, color2.r, d_clamp(wave, 0, 1))),
            math.max(0, d_lerp(color1.g, color2.g, d_clamp(wave, 0, 1))),
            math.max(0, d_lerp(color1.b, color2.b, d_clamp(wave, 0, 1))),
            math.max(0, d_lerp(color1.a, color2.a, d_clamp(wave, 0, 1)))
        )
        final_text = final_text .. '\a' .. color .. text:sub(i, i)
    end
    renderer.text(x, y, color1.r, color1.g, color1.b, color1.a, flags, nil, final_text)
end

local function prevent_mouse(cmd)
    if ui.is_menu_open() then
        cmd.in_attack = false
    end
end

local printc do
    ffi.cdef[[
        typedef struct { uint8_t r; uint8_t g; uint8_t b; uint8_t a; } color_struct_t;
    ]]
    local print_interface = ffi.cast("void***", client.create_interface("vstdlib.dll", "VEngineCvar007"))
    local color_print_fn = ffi.cast("void(__cdecl*)(void*, const color_struct_t&, const char*, ...)", print_interface[0][25])
    local function hex_to_rgb(hex)
        return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
    end
    local function raw(text, r, g, b, a)
        local col = ffi.new("color_struct_t")
        col.r, col.g, col.b, col.a = r or 217, g or 217, b or 217, a or 255
        color_print_fn(print_interface, col, tostring(text))
    end
    printc = function (...)
        for _, v in ipairs{...} do
            local r = "\aD9D9D9" .. v
            for col, text in r:gmatch("\a(%x%x%x%x%x%x)([^\a]*)") do
                raw(text, hex_to_rgb(col))
            end
        end
        raw "\n"
    end
end

local function in_bounds(x1, y1, x2, y2)
    local mouse_x, mouse_y = ui.mouse_position()
    return (mouse_x > x1 and mouse_x < x2) and (mouse_y > y1 and mouse_y < y2)
end

local function extrapolate_position(xpos, ypos, zpos, ticks, player)
    local x, y, z = entity.get_prop(player, "m_vecVelocity")
    for i = 0, ticks do
        xpos = xpos + (x * globals.tickinterval())
        ypos = ypos + (y * globals.tickinterval())
        zpos = zpos + (z * globals.tickinterval())
    end
    return xpos, ypos, zpos
end

math.clamp = function(v, min, max)
    if min > max then min, max = max, min end
    if v > max then return max end
    if v < min then return min end
    return v
end

math.angle_diff = function(dest, src)
    local delta = math.fmod(dest - src, 360.0)
    if dest > src then
        if delta >= 180 then delta = delta - 360 end
    else
        if delta <= -180 then delta = delta + 360 end
    end
    return delta
end

math.angle_normalize = function(angle)
    local ang = math.fmod(angle, 360.0)
    if ang < 0.0 then ang = ang + 360 end
    return ang
end

math.anglemod = function(a)
    return (360 / 65536) * bit.band(math.floor(a * (65536 / 360.0)), 65535)
end

math.approach_angle = function(target, value, speed)
    target = math.anglemod(target)
    value = math.anglemod(value)
    local delta = target - value
    if speed < 0 then speed = -speed end
    if delta < -180 then
        delta = delta + 360
    elseif delta > 180 then
        delta = delta - 360
    end
    if delta > speed then
        value = value + speed
    elseif delta < -speed then
        value = value - speed
    else
        value = target
    end
    return value
end

math.vec_length2d = function(vec)
    return math.sqrt(vec.x * vec
