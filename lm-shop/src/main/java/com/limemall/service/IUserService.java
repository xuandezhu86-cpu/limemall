package com.limemall.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.limemall.domain.dto.LoginFormDTO;
import com.limemall.domain.po.User;
import com.limemall.domain.vo.UserLoginVO;

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

    void deductMoney(String pw, Integer totalFee);
}
