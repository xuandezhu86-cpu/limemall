package com.limemall.user.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.limemall.common.exception.BadRequestException;
import com.limemall.common.exception.BizIllegalException;
import com.limemall.common.exception.ForbiddenException;
import com.limemall.common.utils.UserContext;

import com.limemall.user.config.JwtProperties;
import com.limemall.user.domain.dto.LoginFormDTO;
import com.limemall.user.domain.dto.RegisterFormDTO;
import com.limemall.user.domain.po.User;
import com.limemall.user.domain.vo.UserLoginVO;
import com.limemall.user.enums.UserStatus;
import com.limemall.user.mapper.UserMapper;
import com.limemall.user.service.IUserService;
import com.limemall.user.util.JwtTool;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.Assert;

import java.time.LocalDateTime;

/**
 * <p>
 * 用户表 服务实现类
 * </p>
 *
 * @author LimeMall
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UserServiceImpl extends ServiceImpl<UserMapper, User> implements IUserService {

    private final PasswordEncoder passwordEncoder;

    private final JwtTool jwtTool;

    private final JwtProperties jwtProperties;

    @Override
    public UserLoginVO login(LoginFormDTO loginDTO) {
        // 1.数据校验
        String username = loginDTO.getUsername();
        String password = loginDTO.getPassword();
        // 2.根据用户名或手机号查询
        User user = lambdaQuery().eq(User::getUsername, username).one();
        Assert.notNull(user, "用户名错误");
        // 3.校验是否禁用
        if (user.getStatus() == UserStatus.FROZEN) {
            throw new ForbiddenException("用户被冻结");
        }
        // 4.校验密码
        if (!passwordEncoder.matches(password, user.getPassword())) {
            throw new BadRequestException("用户名或密码错误");
        }
        // 5.生成TOKEN
        String token = jwtTool.createToken(user.getId(), jwtProperties.getTokenTTL());
        // 6.封装VO返回
        UserLoginVO vo = new UserLoginVO();
        vo.setUserId(user.getId());
        vo.setUsername(user.getUsername());
        vo.setBalance(user.getBalance());
        vo.setToken(token);
        return vo;
    }

    @Override
    @Transactional
    public void register(RegisterFormDTO registerDTO) {
        String username = registerDTO.getUsername();
        // 1.两次密码一致性校验（前端已经校验过，后端再兜一次，避免绕过页面直接调接口）
        if (registerDTO.getConfirmPassword() != null
                && !registerDTO.getConfirmPassword().equals(registerDTO.getPassword())) {
            throw new BadRequestException("两次输入的密码不一致");
        }
        // 2.用户名唯一性校验（数据库上还有 uk_username 唯一索引兜底，防并发重复注册）
        User exist = getOne(new LambdaQueryWrapper<User>().eq(User::getUsername, username), false);
        if (exist != null) {
            throw new BizIllegalException("用户名「" + username + "」已被注册，换一个试试");
        }
        // 3.密码用 BCrypt 加密后落库（与登录校验用的是同一个 PasswordEncoder）
        User user = new User()
                .setUsername(username)
                .setPassword(passwordEncoder.encode(registerDTO.getPassword()))
                .setPhone(registerDTO.getPhone())
                .setStatus(UserStatus.NORMAL)
                // 演示用初始余额 1000.00 元，方便注册完直接走通「下单 → 支付」链路；真实项目不会有这笔钱
                .setBalance(100000)
                .setCreateTime(LocalDateTime.now())
                .setUpdateTime(LocalDateTime.now());
        save(user);
        log.info("新用户注册成功 userId={}, username={}", user.getId(), username);
    }

    @Override
    public void deductMoney(String pw, Integer totalFee) {
        log.info("开始扣款");
        // 1.校验密码
        User user = getById(UserContext.getUser());
        if(user == null || !passwordEncoder.matches(pw, user.getPassword())){
            // 密码错误
            throw new BizIllegalException("用户密码错误");
        }

        // 2.尝试扣款
        try {
            baseMapper.updateMoney(UserContext.getUser(), totalFee);
        } catch (Exception e) {
            throw new RuntimeException("扣款失败，可能是余额不足！", e);
        }
        log.info("扣款成功");
    }
}
