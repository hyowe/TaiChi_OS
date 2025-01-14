import logging

import tornado.httpserver
import tornado.ioloop
import tornado.web
import tornado.wsgi
from tornado.options import options

# 引入Flask应用
from core import create_app as make_core_app
# 引入WebSocket-Monitor应用
from websocket.system_usage import monitor_app
# 引入WebSSH应用
from webssh.main import make_app as make_webssh_app
from webssh.settings import get_server_settings, check_encoding_setting


def add_handlers_to_app(app, pattern, handlers):
    """
    将处理程序添加到应用程序中。

    参数:
    app: Tornado web应用程序实例,我们将在其中添加处理程序。
    pattern: 一个字符串,表示URL模式,我们将在其中查找匹配的请求。
    handlers: 一个处理程序类或者函数,当URL匹配到模式时,将会被调用。

    返回:
    无返回值。此函数将处理程序直接添加到提供的应用程序实例中。
    """
    app.add_handlers(r'.*', [(pattern, handlers)])


def main():
    # 解析命令行参数
    options.parse_command_line()

    # 检查编码设置
    check_encoding_setting(options.encoding)

    # 获取当前的I/O循环
    loop = tornado.ioloop.IOLoop.current()

    # 创建主应用
    main_app = tornado.web.Application(debug=True)

    # 添加WebSSH应用
    webssh_app = make_webssh_app(loop, options)
    add_handlers_to_app(main_app, r'/webssh/.*', webssh_app)

    # 添加WebSocket-Monitor应用
    websocket_handlers = monitor_app()
    add_handlers_to_app(main_app, r'.*', websocket_handlers)

    # 添加Flask应用
    flask_app = make_core_app()
    wsgi_app = tornado.wsgi.WSGIContainer(flask_app)
    add_handlers_to_app(main_app, r'.*', wsgi_app)

    try:
        # 获取服务器设置
        server_settings = get_server_settings(options)

        # 启动服务器
        main_app.listen(80, '0.0.0.0', **server_settings)
        logging.info(
            '服务器启动成功! 运行在 {}:{}'.format('0.0.0.0', 80)
        )

        loop.start()
    except KeyboardInterrupt:
        logging.info('服务器已停止')
    except OSError:
        logging.error('服务器启动失败,请检查端口是否被占用')
    except Exception as e:
        logging.error('服务器启动失败,请检查错误日志')
        logging.exception(e)


if __name__ == "__main__":
    main()
