"""Renders the Scry icon SVG to every Android and iOS launcher size with
headless Chrome."""
import os
import re
import subprocess
import sys

svg_path, repo = sys.argv[1], sys.argv[2]
work = os.path.dirname(os.path.abspath(svg_path))
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
PROFILE = os.path.join(work, 'chrome-prof')

svg = open(svg_path, encoding='utf-8').read()
# iOS: a full white square (iOS rounds the corners and forbids transparency).
ios_svg = svg.replace(
    '<rect x="32" y="32" width="960" height="960" rx="200" fill="#ffffff"/>',
    '<rect x="0" y="0" width="1024" height="1024" fill="#ffffff"/>').replace(
    '<clipPath id="tile"><rect x="32" y="32" width="960" height="960" rx="200"/></clipPath>',
    '<clipPath id="tile"><rect x="0" y="0" width="1024" height="1024"/></clipPath>')
assert ios_svg != svg
open(os.path.join(work, 'icon-android.svg'), 'w', encoding='utf-8').write(svg)
open(os.path.join(work, 'icon-ios.svg'), 'w', encoding='utf-8').write(ios_svg)


def render(src, size, dest):
    html = os.path.join(work, f'render-{size}.html')
    open(html, 'w').write(
        f'<html><body style="margin:0;background:transparent">'
        f'<img src="{os.path.basename(src)}" width="{size}" height="{size}" style="display:block">'
        f'</body></html>')
    if os.path.exists(dest):
        os.remove(dest)
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                    f'--user-data-dir={PROFILE}', '--default-background-color=00000000',
                    f'--window-size={size},{size}', f'--screenshot={dest}',
                    'file:///' + html.replace('\\', '/')],
                   capture_output=True, timeout=60)
    with open(dest, 'rb') as f:
        head = f.read(24)
    w = int.from_bytes(head[16:20], 'big')
    h = int.from_bytes(head[20:24], 'big')
    assert (w, h) == (size, size), (dest, w, h)


res = os.path.join(repo, 'android', 'app', 'src', 'main', 'res')
for folder, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    render(os.path.join(work, 'icon-android.svg'), size,
           os.path.join(res, f'mipmap-{folder}', 'ic_launcher.png'))
    print('android', folder, size)

icons = os.path.join(repo, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
for name in sorted(os.listdir(icons)):
    m = re.match(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$', name)
    if not m:
        continue
    size = round(float(m.group(1)) * int(m.group(2)))
    render(os.path.join(work, 'icon-ios.svg'), size, os.path.join(icons, name))
    print('ios', name, size)
