package com.limemall.user.domain.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotNull;
import javax.validation.constraints.Pattern;
import javax.validation.constraints.Size;

/**
 * 注册表单实体。
 */
@Data
@ApiModel(description = "注册表单实体")
public class RegisterFormDTO {

    @ApiModelProperty(value = "用户名", required = true)
    @NotNull(message = "用户名不能为空")
    @Pattern(regexp = "^[a-zA-Z0-9_]{4,20}$", message = "用户名需为 4~20 位字母、数字或下划线")
    private String username;

    @ApiModelProperty(value = "密码", required = true)
    @NotNull(message = "密码不能为空")
    @Size(min = 6, max = 20, message = "密码长度需为 6~20 位")
    private String password;

    @ApiModelProperty("确认密码（可为空，前端已校验时后端不重复校验）")
    private String confirmPassword;

    @ApiModelProperty("手机号（可选）")
    @Pattern(regexp = "^$|^1[3-9]\\d{9}$", message = "手机号格式不正确")
    private String phone;
}
