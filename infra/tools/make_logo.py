"""生成「青柠商城 LimeMall」品牌图（门户与后台的 logo 素材）。

用法： python make_logo.py
依赖： Pillow
输出：
  <项目>/lm-nginx/html/lm-portal/img/logo.png    394x135  门户顶部/登录页
  <项目>/lm-nginx/html/lm-console/images/1.png   256x256  运营后台登录图标
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

LIME = (124, 194, 66)
LIME_DARK = (92, 152, 44)
DARK = (54, 60, 66)
WHITE = (255, 255, 255)

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
HTML = None
for name in os.listdir(os.path.join(BASE)):
    if os.path.isdir(os.path.join(BASE, name)) and os.path.exists(os.path.join(BASE, name, 'pom.xml')):
        HTML = os.path.join(BASE, name, 'lm-nginx', 'html')
if not HTML or not os.path.isdir(HTML):
    raise SystemExit('lm-nginx/html not found under ' + BASE)


def font(size, bold=True):
    for p in (r'C:\Windows\Fonts\msyhbd.ttc' if bold else r'C:\Windows\Fonts\msyh.ttc',
              r'C:\Windows\Fonts\msyh.ttc',
              r'C:\Windows\Fonts\simhei.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def lime_slice(d, cx, cy, r):
    """青柠切片：绿色外皮 + 白色果肉 + 8 瓣"""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=LIME)
    ir = int(r * 0.86)
    d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=WHITE)
    for i in range(8):
        a0 = math.radians(i * 45 + 4)
        a1 = math.radians((i + 1) * 45 - 4)
        pts = [(cx, cy),
               (cx + ir * 0.9 * math.cos(a0), cy + ir * 0.9 * math.sin(a0)),
               (cx + ir * 0.9 * math.cos(a1), cy + ir * 0.9 * math.sin(a1))]
        d.polygon(pts, fill=LIME)


def make_portal_logo(path):
    im = Image.new('RGBA', (394, 135), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    lime_slice(d, 62, 67, 50)
    d.text((128, 24), '青柠商城', font=font(46), fill=DARK)
    d.text((132, 84), 'LIMEMALL.COM', font=font(23), fill=LIME_DARK)
    im.save(path)
    print('  ->', path, im.size)


def make_console_icon(path):
    im = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    lime_slice(d, 128, 128, 108)
    im.save(path)
    print('  ->', path, im.size)


if __name__ == '__main__':
    make_portal_logo(os.path.join(HTML, 'lm-portal', 'img', 'logo.png'))
    make_console_icon(os.path.join(HTML, 'lm-console', 'images', '1.png'))
