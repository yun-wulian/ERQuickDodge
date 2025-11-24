-- 配置选项
DODGE_INSTANTLY = TRUE -- 按下闪避键时立即闪避，而不是释放按键时闪避
BACKSTEP_REPLACE_BACKWARDS_DODGE = FALSE -- 向后闪避时，使用后撤步替代
SPRINTING_R2_ON_BACKSTEP_R2 = TRUE -- 在后撤步中按下R2时，执行奔跑R2攻击而不是站立R2攻击
INSTANT_SPRINTING_FROM_DODGE = TRUE -- 如果在闪避中按住闪避键，将在闪避结束后立即进入奔跑状态
SPRINTING_ATTACKS_WHILE_HOLDING_DODGE = TRUE -- 如果在闪避中按住闪避键，将排队执行奔跑攻击而不是闪避攻击
FAST_DODGE_R2 = FALSE -- 从闪避中退出时，R2攻击会明显更快
FIRST_R1_CHAINS_TO_SECOND_R2 = FALSE -- 站立R1连击连接到第二个站立R2而不是第一个站立R2
DODGE_R1_CHAINS_TO_SECOND_R2 = FALSE -- 闪避R1连击连接到第二个R2
SPRINT_R1_CHAINS_TO_SECOND_R2 = FALSE -- 奔跑R1连击连接到第二个R2
BACKSTEP_R1_CHAINS_TO_SECOND_R2 = FALSE -- 后撤步R1连击连接到第二个R2
SPRINT_R2_CHAINS_TO_SECOND_R2 = FALSE -- 奔跑R2连击连接到第二个R2

-- 闪避取消的宽限期（以秒为单位）。在此时间窗口内可以取消攻击进行闪避
DODGE_CANCEL_GRACE_PERIOD = 0.5

DODGE_CONTINUE_SPRINT = TRUE --长按闪避，会接续闪避到疾跑
DODGE_CANCEL = TRUE --闪避可以取消动作
JUMP_CANCEL = TRUE  --跳跃可以取消动作
GUARD_CANCEL = TRUE

-- 创建替换函数的函数
function createReplacement(originalFunction, newFunction)
    -- 在新函数的环境中存储原始函数
    local original = originalFunction
    return function(...)
        -- 调用新函数
        return newFunction(...)
    end
end

-- 创建钩子函数的函数（先执行新函数，再执行原始函数）
function createDetour(originalFunction, newFunction)
    -- 在新函数的环境中存储原始函数
    local original = originalFunction
    -- 创建一个包装器，先调用新函数，然后调用原始函数
    return function(...)
        -- 调用新函数
        newFunction(...)
        -- 调用原始函数
        return original(...)
    end
end

-- 创建后置钩子函数的函数（先执行原始函数，再执行新函数）
function createPostDetour(originalFunction, newFunction)
    -- 在新函数的环境中存储原始函数
    local original = originalFunction
    -- 创建一个包装器，先调用原始函数，然后调用新函数
    return function(...)
        -- 调用原始函数
        local originalResult = original(...)
        -- 调用新函数
        newFunction(...)
        return originalResult
    end
end

-- 初始化全局事件日志
rawset(_G, "g_EventsLog", { ["CMSG"] = "", ["TIME"] = 0 })

-- 记录事件和时间的函数
function LogEventsAndTiming(state)
    g_EventsLog["CMSG"] = state
    g_EventsLog["TIME"] = os.clock()
end

-- 在ExecEvent函数上添加钩子，记录事件
ExecEvent = createDetour(ExecEvent, LogEventsAndTiming)

-- 修复闪避角度的函数
function fixDodges()
    c_RollingAngle = GetVariable("MoveAngle")
    c_ArtsRollingAngle = GetVariable("MoveAngle")
end

-- 在GetConstVariable函数上添加后置钩子，修复闪避
GetConstVariable = createPostDetour(GetConstVariable, fixDodges)

-- 设置全局更新标志
rawset(_G, "canUpdateSelf", true)

-- 自定义获取闪避请求的函数
function GetEvasionRequestCustom()
    local dodgeDecider = FALSE

    -- 根据配置决定使用哪种闪避判定
    if DODGE_INSTANTLY == TRUE then
        dodgeDecider = env(ActionRequest, ACTION_ARM_SP_MOVE)
    else
        dodgeDecider = env(ActionRequest, ACTION_ARM_ROLLING)
    end

    local move_angle = GetVariable("MoveAngle") -- 获取移动角度
    local stick_level = GetVariable("MoveSpeedLevel") -- 获取摇杆推杆程度

    -- 如果耐力不足，返回无效请求
    if env(GetStamina) < STAMINA_MINIMUM then
        return ATTACK_REQUEST_INVALID
    end
    
    -- 根据摇杆输入和配置决定闪避类型
    if dodgeDecider == TRUE and stick_level > 0.05 then
        if (move_angle > 135 or move_angle < -135) and BACKSTEP_REPLACE_BACKWARDS_DODGE == TRUE then
            return ATTACK_REQUEST_BACKSTEP -- 后撤步
        else
            return ATTACK_REQUEST_ROLLING -- 翻滚
        end
    elseif env(ActionDuration, ACTION_ARM_L1) > 0 then
        if env(ActionRequest, ACTION_ARM_EMERGENCYSTEP) == TRUE then
            if env(IsEmergencyEvasionPossible, 0) == TRUE or env(IsEmergencyEvasionPossible, 1) == TRUE then
                return ATTACK_REQUEST_EMERGENCYSTEP -- 紧急闪避
            end
        elseif env(ActionRequest, ACTION_ARM_BACKSTEP) == TRUE then
            return ATTACK_REQUEST_BACKSTEP -- 后撤步
        else
            return ATTACK_REQUEST_INVALID -- 无效请求
        end
    elseif env(ActionRequest, ACTION_ARM_BACKSTEP) == TRUE then
        return ATTACK_REQUEST_BACKSTEP -- 后撤步
    end
    
    return ATTACK_REQUEST_INVALID -- 默认返回无效请求
end

-- 自定义默认后撤步更新函数
function DefaultBackStep_onUpdateCustom()
    act(DisallowAdditiveTurning, TRUE) -- 禁止附加转向

    -- 调用通用闪避函数处理攻击输入
    if EvasionCommonFunction(FALL_TYPE_DEFAULT, "W_AttackRightBackstep", "W_AttackRightHeavyDash",
        "W_AttackLeftLight1", "W_AttackLeftHeavy1", "W_AttackBothBackstep", "W_AttackBothHeavyDash",
        QUICKTYPE_BACKSTEP) == TRUE then
        return
    end
end

-- 当前按住时间变量
local currentHoldTime = 0

-- 自定义翻滚更新函数
function Rolling_onUpdateCustom()
    act(DisallowAdditiveTurning, TRUE) -- 禁止附加转向
    SetThrowAtkInvalid() -- 设置投掷攻击无效

    -- 如果有特定特效，重置伤害计数
    if env(GetSpEffectID, 100390) == TRUE then
        ResetDamageCount()
    end

    SetEnableAimMode() -- 启用瞄准模式

    -- 新增：累计按住时间检测
    if DODGE_CONTINUE_SPRINT == TRUE then
        if env(ActionDuration, ACTION_ARM_SP_MOVE) > 0 then
            currentHoldTime = currentHoldTime + GetDeltaTime() -- 累加按住时间
            if currentHoldTime >= 0.35 then                -- 如果按住时间超过0.35秒
                --ExecEventNoReset("W_Jump_Land_To_Dash")
                ExecEventNoReset("W_Idle")                 -- 执行空闲状态
                SetVariable("MoveSpeedLevelReal", 2)       -- 设置移动速度等级
                currentHoldTime = 0                        -- 重置计时器
                return
            end
        else
            currentHoldTime = 0 -- 没有按住时重置计时器
        end
    end

    -- 原有的攻击检测逻辑
    -- 根据配置选择不同的攻击类型
    if SPRINTING_ATTACKS_WHILE_HOLDING_DODGE == TRUE and env(ActionDuration, ACTION_ARM_SP_MOVE) > 0 then
        if EvasionCommonFunction(FALL_TYPE_DEFAULT, "W_AttackRightLightDash", "W_AttackRightHeavyDash", "W_AttackLeftLight1", "W_AttackLeftHeavy1", "W_AttackBothDash", "W_AttackBothHeavyDash", QUICKTYPE_ROLLING) == TRUE then
            return
        end
    elseif FAST_DODGE_R2 == TRUE then
        if EvasionCommonFunction(FALL_TYPE_DEFAULT, "W_AttackRightLightStep", "W_AttackRightHeavy1End", "W_AttackLeftLight1", "W_AttackLeftHeavy1", "W_AttackBothLightStep", "W_AttackBothHeavy1End", QUICKTYPE_ROLLING) == TRUE then
            return
        end
    else
        if EvasionCommonFunction(FALL_TYPE_DEFAULT, "W_AttackRightLightStep", "W_AttackRightHeavy1Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1", "W_AttackBothLightStep", "W_AttackBothHeavy1Start", QUICKTYPE_ROLLING) == TRUE then
            return
        end
    end

    -- 动画结束时返回空闲状态
    if env(IsAnimEnd, 1) == TRUE then
        ExecEventAllBody("W_Idle")
        currentHoldTime = 0
        return
    end
    
    SetRollingTurnCondition(FALSE) -- 设置翻滚转向条件
    
    -- 原有的奔跑检测（在翻滚结束时）
    if env(ActionDuration, ACTION_ARM_L1) > 0 then
        currentHoldTime = 0
        ExecEventNoReset("W_Jump_Land_To_Dash") -- 执行落地到奔跑的转换
    end
    
    -- 设置切换奔跑变量
    if env(ActionDuration, ACTION_ARM_SP_MOVE) > 0 and SPRINTING_ATTACKS_WHILE_HOLDING_DODGE == TRUE then
        SetVariable("ToggleDash", 1)
    end
end

-- 自定义右手轻攻击1更新函数
function AttackRightLight1_onUpdateCustom()
    local r1 = "W_AttackRightLight2" -- 默认连击

    if g_ComboReset == TRUE then
        r1 = "W_AttackRightLight1" -- 连击重置时使用第一击
    end
    
    -- 根据配置选择不同的重攻击连击
    if FIRST_R1_CHAINS_TO_SECOND_R2 == TRUE then
        if AttackCommonFunction(r1, "W_AttackRightHeavy2Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
            "W_AttackBothLight2", "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
            return
        end
    else
        if AttackCommonFunction(r1, "W_AttackRightHeavy1Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
            "W_AttackBothLight2", "W_AttackBothHeavy1Start", FALSE, TRUE, 1) == TRUE then
            return
        end
    end
end

-- 自定义双手轻攻击1更新函数
function AttackBothLight1_onUpdateCustom()
    local b1 = "W_AttackBothLight2" -- 默认连击
    if g_ComboReset == TRUE then
        b1 = "W_AttackBothLight1" -- 连击重置时使用第一击
    end
    
    -- 根据配置选择不同的重攻击连击
    if FIRST_R1_CHAINS_TO_SECOND_R2 == TRUE then
        if AttackCommonFunction("W_AttackRightLight2", "W_AttackRightHeavy2Start", "W_AttackBothLeft2",
            "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
            return
        end
    else
        if AttackCommonFunction("W_AttackRightLight2", "W_AttackRightHeavy1Start", "W_AttackBothLeft2",
            "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy1Start", FALSE, TRUE, 1) == TRUE then
            return
        end
    end
end

-- 自定义右手轻步攻击更新函数
function AttackRightLightStep_onUpdateCustom()
    local r1 = "W_AttackRightLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        r1 = "W_AttackRightLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction(r1, "W_AttackRightHeavy2Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
        "W_AttackBothLight1", "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义双手轻步攻击更新函数
function AttackBothLightStep_onUpdateCustom()
    local b1 = "W_AttackBothLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        b1 = "W_AttackBothLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction("W_AttackRightLight1", "W_AttackRightHeavy2Start", "W_AttackLeftLight1",
        "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义右手轻奔跑攻击更新函数
function AttackRightLightDash_onUpdateCustom()
    local r1 = "W_AttackRightLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        r1 = "W_AttackRightLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction(r1, "W_AttackRightHeavy2Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
        "W_AttackBothLight1", "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义双手奔跑攻击更新函数
function AttackBothDash_onUpdateCustom()
    local b1 = "W_AttackBothLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        b1 = "W_AttackBothLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction("W_AttackRightLight1", "W_AttackRightHeavy2Start", "W_AttackLeftLight1",
        "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义右手后撤步攻击更新函数
function AttackRightBackstep_onUpdateCustom()
    local r1 = "W_AttackRightLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        r1 = "W_AttackRightLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction(r1, "W_AttackRightHeavy2Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
        "W_AttackBothLight1", "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义双手后撤步攻击更新函数
function AttackBothBackstep_onUpdateCustom()
    local b1 = "W_AttackBothLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        b1 = "W_AttackBothLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction("W_AttackRightLight1", "W_AttackRightHeavy2Start", "W_AttackLeftLight1",
        "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义右手重奔跑攻击更新函数
function AttackRightHeavyDash_onUpdateCustom()
    local r1 = "W_AttackRightLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        r1 = "W_AttackRightLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction(r1, "W_AttackRightHeavy2Start", "W_AttackLeftLight1", "W_AttackLeftHeavy1",
        "W_AttackBothLight1", "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end

-- 自定义双手重奔跑攻击更新函数
function AttackBothHeavyDash_onUpdateCustom()
    local b1 = "W_AttackBothLightSubStart" -- 默认连击起始
    if g_ComboReset == TRUE then
        b1 = "W_AttackBothLight1" -- 连击重置时使用第一击
    end
    
    -- 调用通用攻击函数
    if AttackCommonFunction("W_AttackRightLight1", "W_AttackRightHeavy2Start", "W_AttackLeftLight1",
        "W_AttackLeftHeavy1", b1, "W_AttackBothHeavy2Start", FALSE, TRUE, 1) == TRUE then
        return
    end
end
function Game_IsPlayer()
	if env(IsCOMPlayer) == FALSE then
		return TRUE
	end

	return FALSE
end

function Action_IsJumping()
	if env(IsLanding) == FALSE then
		return TRUE
	end

	return FALSE
end

function DoJump()
    if env(1116, 102360) == FALSE then
        AddStamina(STAMINA_REDUCE_JUMP)
    end
    local style = c_Style
    if style == HAND_RIGHT then
        SetVariable("JumpAttack_HandCondition", 0)
    elseif style == HAND_RIGHT_BOTH then
        SetVariable("JumpAttack_HandCondition", 1)
    elseif style == HAND_LEFT_BOTH then
        if GetEquipType(HAND_LEFT, WEAPON_CATEGORY_CROSSBOW) == TRUE then
            SetVariable("JumpAttack_HandCondition", 4)
        else
            SetVariable("JumpAttack_HandCondition", 1)
        end
    end
    SetVariable("JumpAttackForm", 0)
    SetVariable("JumpUseMotion_Bool", false)
    SetVariable("JumpMotion_Override", 0.009999999776482582)
    SetVariable("JumpAttack_Land", 0)
    SetVariable("SwingPose", 0)
    if GetVariable("IsEnableToggleDashTest") == 2 then
        SetVariable("ToggleDash", 0)
    end
    local JumpMoveLevel = 0
    if GetVariable("LocomotionState") == 1 and GetVariable("MoveSpeedIndex") == 2 then
        JumpMoveLevel = 2
    elseif GetVariable("MoveSpeedLevel") >= 0.6000000238418579 then
        JumpMoveLevel = 1
    end
    if env(1116, 503520) == TRUE then
        JumpMoveLevel = 0
    elseif env(1116, 5520) == TRUE then
        JumpMoveLevel = 0
    elseif env(1116, 425) == TRUE then
        JumpMoveLevel = 0
    elseif env(1116, 4101) == TRUE then
        JumpMoveLevel = 0
    elseif env(1116, 4100) == TRUE then
        JumpMoveLevel = 0
    elseif env(1116, 19670) == TRUE then
        JumpMoveLevel = 0
    end
    if JumpMoveLevel == 2 then
        if env(700) == TRUE then
            act(4001)
        end
        act(2025, env(404))
        SetAIActionState()
        ExecEvent("W_Jump_D")
        return TRUE
    elseif JumpMoveLevel == 1 then
        if GetVariable("IsLockon") == FALSE and env(234) == FALSE and env(1007) == FALSE then
            SetVariable("JumpDirection", 0)
            SetVariable("JumpAngle", 0)
        else
            local turn_target_angle = 0
            local jumpangle = env(407) * 0.009999999776482582
            if jumpangle > -45 and jumpangle < 45 then
                turn_target_angle = jumpangle
                SetVariable("JumpDirection", 0)
                SetVariable("JumpAngle", 0)
            elseif jumpangle >= 0 and jumpangle <= 100 then
                turn_target_angle = jumpangle - 90
                SetVariable("JumpDirection", 3)
                SetVariable("JumpAngle", 90)
            elseif jumpangle >= -100 and jumpangle <= 0 then
                turn_target_angle = jumpangle + 90
                SetVariable("JumpDirection", 2)
                SetVariable("JumpAngle", -90)
            else
                turn_target_angle = jumpangle - 180
                SetVariable("JumpDirection", 1)
                SetVariable("JumpAngle", 180)
            end
            if GetVariable("IsLockon") == true then
                act(2019, turn_target_angle)
            else
                act(2029, turn_target_angle)
            end
        end
        SetVariable("IsEnableDirectionJumpTAE", true)
        if env(700) == TRUE then
            act(4001)
        end
        act(2025, env(404))
        SetAIActionState()
        ExecEvent("W_Jump_F")
        return TRUE
    else
        SetVariable("JumpReachSelector", 0)
        if env(700) == TRUE then
            act(4001)
        end
        act(2025, env(404))
        SetAIActionState()
        ExecEvent("W_Jump_N")
        return TRUE
    end
end

IsRollingPressed = FALSE
IsGuardingPressed = FALSE
LastCancelRollingTime = 0
LastCancelGuardTime = 0
function myUpdates()
    if Game_IsPlayer() == TRUE and env(IsOnMount) == FALSE then
        if (env(ActionDuration, ACTION_ARM_SP_MOVE) > 0) and Action_IsJumping() == FALSE and IsRollingPressed == FALSE and DODGE_CANCEL == TRUE and os.clock() - LastCancelRollingTime > DODGE_CANCEL_GRACE_PERIOD then
            IsRollingPressed = TRUE
            if GetVariable("MoveSpeedLevel") > 0.05 then
                ExecEvent("W_Rolling")
            else
                if IsEnableGuard() == TRUE and IsGuard() == TRUE then
                    SetVariable("BackStepGuardLayer", 1)
                    SetVariable("EnableTAE_BackStep", false)
                    ExecEvent("W_DefaultBackStep")
                    ExecEvent("W_BackStepGuardOn_UpperLayer")
                else
                    SetVariable("BackStepGuardLayer", 0)
                    SetVariable("EnableTAE_BackStep", true)
                    ExecEventAllBody("W_DefaultBackStep")
                end
            end
            LastCancelRollingTime = os.clock()
        end
        if (env(ActionDuration, 2) > 0) and Action_IsJumping() == FALSE and IsGuardingPressed == FALSE and GUARD_CANCEL == TRUE and os.clock() - LastCancelGuardTime > DODGE_CANCEL_GRACE_PERIOD then
            IsGuardingPressed = TRUE
            ExecGuard(Event_GuardStart, ALLBODY)
            LastCancelGuardTime = os.clock()
        end
        if (env(ActionRequest, 6) == TRUE or env(ActionDuration, 6) > 0) and Action_IsJumping() == FALSE and JUMP_CANCEL == TRUE then
            DoJump()
        end

        if env(ActionDuration, ACTION_ARM_SP_MOVE) == 0 and IsRollingPressed == TRUE then
            IsRollingPressed = FALSE
        end 
        if env(ActionDuration, 2) == 0 and IsGuardingPressed == TRUE then
            IsGuardingPressed = FALSE
        end
    end
end



-- 在Update函数上添加钩子
Update = createDetour(Update, myUpdates)

-- 根据配置替换相应的函数
GetEvasionRequest = createReplacement(GetEvasionRequest, GetEvasionRequestCustom)
if SPRINTING_R2_ON_BACKSTEP_R2 == TRUE then
    DefaultBackStep_onUpdate = createReplacement(DefaultBackStep_onUpdate, DefaultBackStep_onUpdateCustom)
end
if INSTANT_SPRINTING_FROM_DODGE == TRUE then
    Rolling_onUpdate = createReplacement(Rolling_onUpdate, Rolling_onUpdateCustom)
end
if FIRST_R1_CHAINS_TO_SECOND_R2 == TRUE then
    AttackRightLight1_onUpdate = createReplacement(AttackRightLight1_onUpdate, AttackRightLight1_onUpdateCustom)
    AttackBothLight1_onUpdate = createReplacement(AttackBothLight1_onUpdate, AttackBothLight1_onUpdateCustom)
end
if DODGE_R1_CHAINS_TO_SECOND_R2 == TRUE then
    AttackRightLightStep_onUpdate = createReplacement(AttackRightLightStep_onUpdate, AttackRightLightStep_onUpdateCustom)
    AttackBothLightStep_onUpdate = createReplacement(AttackBothLightStep_onUpdate, AttackBothLightStep_onUpdateCustom)
end
if SPRINT_R1_CHAINS_TO_SECOND_R2 == TRUE then
    AttackRightLightDash_onUpdate = createReplacement(AttackRightLightDash_onUpdate, AttackRightLightDash_onUpdateCustom)
    AttackBothDash_onUpdate = createReplacement(AttackBothDash_onUpdate, AttackBothDash_onUpdateCustom)
end
if BACKSTEP_R1_CHAINS_TO_SECOND_R2 == TRUE then
    AttackRightBackstep_onUpdate = createReplacement(AttackRightBackstep_onUpdate, AttackRightBackstep_onUpdateCustom)
    AttackBothBackstep_onUpdate = createReplacement(AttackBothBackstep_onUpdate, AttackBothBackstep_onUpdateCustom)
end
if SPRINT_R2_CHAINS_TO_SECOND_R2 == TRUE then
    AttackRightHeavyDash_onUpdate = createReplacement(AttackRightHeavyDash_onUpdate, AttackRightHeavyDash_onUpdateCustom)
    AttackBothHeavyDash_onUpdate = createReplacement(AttackBothHeavyDash_onUpdate, AttackBothHeavyDash_onUpdateCustom)
end