package com.limemall.user.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.limemall.user.domain.dto.LoginFormDTO;
import com.limemall.user.domain.dto.RegisterFormDTO;
import com.limemall.user.domain.po.User;
import com.limemall.user.domain.vo.UserLoginVO;

/**
 * <p>
 * 用户表 服务类
 * </p>
 *
 * @author LimeMall
 * @since 2023-05-05
 */
public interface IUserService extends IService<User> {

    UserLoginVO login(LoginFormDTO loginFormDTO);

    /**
     * 用户注册：校验用户名唯一后，密码加密落库。
     */
    void register(RegisterFormDTO registerFormDTO);

    void deductMoney(String pw, Integer totalFee);
}
