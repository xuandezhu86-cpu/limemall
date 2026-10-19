# 官方 rabbitmq:3.8-management 不自带延迟消息插件（x-delayed-message），
# 而 trade-service 的 OrderDelayMessageListener 用到了 delayed = "true"，
# 所以这里把社区插件打进镜像。
#
# 插件包来源：https://github.com/rabbitmq/rabbitmq-delayed-message-exchange/releases/tag/v3.8.0
# 版本必须与 broker 大版本一致（3.8 broker 用 3.8.0 插件）。
FROM rabbitmq:3.8-management

COPY rabbitmq_delayed_message_exchange-3.8.0.ez /opt/rabbitmq/plugins/

# --offline 表示不启动 broker，只写 enabled_plugins 文件
RUN rabbitmq-plugins enable --offline rabbitmq_delayed_message_exchange
