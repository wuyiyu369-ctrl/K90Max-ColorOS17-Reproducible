from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUTPUT = Path(
    r"D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Stage48_发帖文档.docx"
)


def set_run_font(run, name="Microsoft YaHei", size=11, bold=None, color="000000"):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    run.font.color.rgb = RGBColor.from_string(color)


def shade_cell(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=110, start=130, bottom=110, end=130):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for key, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{key}"))
        if node is None:
            node = OxmlElement(f"w:{key}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_borders(table, color="D9D9D9", size="8"):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = borders.find(qn(f"w:{edge}"))
        if el is None:
            el = OxmlElement(f"w:{edge}")
            borders.append(el)
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), size)
        el.set(qn("w:color"), color)


def keep_with_next(paragraph):
    paragraph.paragraph_format.keep_with_next = True


def add_heading(doc, text, level=1):
    p = doc.add_paragraph(style=f"Heading {level}")
    p.paragraph_format.space_before = Pt(14 if level == 1 else 9)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    set_run_font(r, size=14 if level == 1 else 12, bold=True)
    return p


def add_body(doc, text, bold_lead=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.25
    if bold_lead and text.startswith(bold_lead):
        r1 = p.add_run(bold_lead)
        set_run_font(r1, bold=True)
        r2 = p.add_run(text[len(bold_lead):])
        set_run_font(r2)
    else:
        r = p.add_run(text)
        set_run_font(r)
    return p


def add_bullet(doc, text, level=0):
    style = "List Bullet" if level == 0 else "List Bullet 2"
    p = doc.add_paragraph(style=style)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.2
    r = p.add_run(text)
    set_run_font(r)
    return p


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


doc = Document()
section = doc.sections[0]
section.page_width = Inches(8.5)
section.page_height = Inches(11)
section.top_margin = Inches(0.72)
section.bottom_margin = Inches(0.68)
section.left_margin = Inches(0.78)
section.right_margin = Inches(0.78)

styles = doc.styles
normal = styles["Normal"]
normal.font.name = "Microsoft YaHei"
normal._element.rPr.rFonts.set(qn("w:eastAsia"), "Microsoft YaHei")
normal.font.size = Pt(11)
for style_name in ("Title", "Subtitle", "Heading 1", "Heading 2"):
    style = styles[style_name]
    style.font.name = "Microsoft YaHei"
    style._element.rPr.rFonts.set(qn("w:eastAsia"), "Microsoft YaHei")
    style.font.color.rgb = RGBColor(0, 0, 0)

title = doc.add_paragraph(style="Title")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title.paragraph_format.space_after = Pt(6)
title_ppr = title._p.get_or_add_pPr()
title_border = title_ppr.find(qn("w:pBdr"))
if title_border is not None:
    title_ppr.remove(title_border)
title_border = OxmlElement("w:pBdr")
title_bottom = OxmlElement("w:bottom")
title_bottom.set(qn("w:val"), "nil")
title_border.append(title_bottom)
title_ppr.append(title_border)
r = title.add_run("Redmi K90 Max ColorOS 17 Stage48 移植刷机包")
set_run_font(r, size=20, bold=True)

subtitle = doc.add_paragraph(style="Subtitle")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
subtitle.paragraph_format.space_after = Pt(15)
r = subtitle.add_run("正式发布说明与刷机须知")
set_run_font(r, size=11, color="555555")

intro = doc.add_paragraph()
intro.paragraph_format.space_after = Pt(12)
intro.paragraph_format.line_spacing = 1.3
r = intro.add_run(
    "本版本面向 Redmi K90 Max（设备代号 prague），基于 ColorOS 17 移植环境制作。"
    "Stage48 已完成保数据实机刷入和开机验证，并重点修正游戏性能场景的识别、进入与退出状态。"
    "发布包同时提供中文一键刷机向导、Root 选择和明确的敏感分区保护。"
)
set_run_font(r, size=11.5)

add_heading(doc, "基础信息")
info = [
    ("适配机型", "Redmi K90 Max"),
    ("设备代号", "prague"),
    ("系统版本", "ColorOS 17"),
    ("发布版本", "Stage48 CPU SCENE STATEFIX"),
    ("更新时间", "2026年11月7日"),
    ("刷机方式", "fastboot 和 fastbootd 中文一键线刷"),
    ("数据选项", "支持系统更新保留数据，也支持全新刷入"),
    ("Root 选项", "刷机末尾可选择官方无 Root 或 KernelSU init boot"),
    ("作者", "哆啦A梦"),
]
table = doc.add_table(rows=1, cols=2)
table.alignment = WD_TABLE_ALIGNMENT.CENTER
table.autofit = False
table.columns[0].width = Inches(1.65)
table.columns[1].width = Inches(5.15)
table.rows[0].cells[0].text = "项目"
table.rows[0].cells[1].text = "内容"
set_repeat_table_header(table.rows[0])
for c in table.rows[0].cells:
    shade_cell(c, "374151")
    c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_margins(c)
    for p in c.paragraphs:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for run in p.runs:
            set_run_font(run, size=10.5, bold=True, color="FFFFFF")
for idx, (key, value) in enumerate(info):
    cells = table.add_row().cells
    cells[0].text = key
    cells[1].text = value
    if idx % 2:
        shade_cell(cells[0], "F5F7FA")
        shade_cell(cells[1], "F5F7FA")
    for ci, c in enumerate(cells):
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(c)
        for p in c.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if ci == 0 else WD_ALIGN_PARAGRAPH.LEFT
            for run in p.runs:
                set_run_font(run, size=10.5, bold=(ci == 0))
set_table_borders(table)

add_heading(doc, "更新亮点与修复")
add_bullet(doc, "修复游戏性能场景状态：前台游戏能够进入对应性能场景，退出游戏返回桌面后会释放场景并恢复默认状态。")
add_bullet(doc, "内置无 Root 运行链：性能桥由系统启动，不依赖 KernelSU 或 LSPosed 才能完成游戏场景识别和释放。")
add_bullet(doc, "保留小米温控保护：性能场景不会绕过硬件温度保护，温度升高时系统仍会按底层策略限制频率。")
add_bullet(doc, "完善一键刷机体验：支持 ADB、bootloader fastboot 和 fastbootd 状态识别，并提供中文步骤和刷写进度。")
add_bullet(doc, "提供更新与全新刷入两种流程：更新模式优先保留数据；全新刷入可由用户选择是否格式化。")
add_bullet(doc, "提供 Root 选择：刷机末尾可选择官方无 Root init boot，或本机验证过的 KernelSU init boot。")
add_bullet(doc, "加强刷机安全检查：设备数量、分区刷写返回值、数据线和电量要求均有明确提示，失败时立即停止。")

add_heading(doc, "实机验证结果")
add_body(doc, "Stage48 已在 Redmi K90 Max 实机通过保数据刷入，super.img 的 46 个 sparse 分块均返回 OKAY，刷写过程中未擦除 userdata 和 metadata。")
verified = [
    ("系统启动", "sys.boot_completed=1，正常进入系统"),
    ("安全状态", "SELinux Enforcing"),
    ("性能服务", "k90 performance bridge 与原生桥服务均处于 running"),
    ("游戏识别", "和平精英前台包 com.tencent.tmgp.pubgmhd 进入 sconfig 20"),
    ("退出释放", "返回桌面后释放托管游戏场景，sconfig 恢复为 -1"),
    ("频率验证", "低温验证中大核最高达到 4.21 GHz；温度升高时由小米温控主动收紧"),
]
vtable = doc.add_table(rows=1, cols=2)
vtable.alignment = WD_TABLE_ALIGNMENT.CENTER
vtable.autofit = False
vtable.columns[0].width = Inches(1.55)
vtable.columns[1].width = Inches(5.25)
vtable.rows[0].cells[0].text = "验证项"
vtable.rows[0].cells[1].text = "结果"
set_repeat_table_header(vtable.rows[0])
for c in vtable.rows[0].cells:
    shade_cell(c, "374151")
    set_cell_margins(c)
    for p in c.paragraphs:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for run in p.runs:
            set_run_font(run, size=10.5, bold=True, color="FFFFFF")
for idx, (key, value) in enumerate(verified):
    cells = vtable.add_row().cells
    cells[0].text = key
    cells[1].text = value
    if idx % 2:
        shade_cell(cells[0], "F5F7FA")
        shade_cell(cells[1], "F5F7FA")
    for ci, c in enumerate(cells):
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(c)
        for p in c.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if ci == 0 else WD_ALIGN_PARAGRAPH.LEFT
            for run in p.runs:
                set_run_font(run, size=10.5, bold=(ci == 0))
set_table_borders(vtable)

add_heading(doc, "刷机方式")
steps = [
    "确认手机电量高于 30%，使用原厂或质量可靠且没有损坏的数据线。",
    "将一键 EXE、K90 UPDATE 压缩包和 5 个 K90 PAYLOAD 分卷放在同一目录，不要改名。",
    "双击一键刷机包 EXE，选择空间充足的解压目录，等待中文刷机向导自动启动。",
    "按照向导输入 OK，并选择系统更新或全新刷入；需要 Root 时再选择 KernelSU 镜像。",
    "进入关键分区和 super.img 刷写阶段后不要拔线，不要关闭窗口，也不要让电脑休眠。",
    "刷机完成后按提示选择保留或删除解压出的刷机文件。",
]
for index, step in enumerate(steps, start=1):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.05)
    p.paragraph_format.first_line_indent = Inches(-0.05)
    p.paragraph_format.space_after = Pt(5)
    p.paragraph_format.line_spacing = 1.2
    r1 = p.add_run(f"{index}. ")
    set_run_font(r1, bold=True)
    r2 = p.add_run(step)
    set_run_font(r2)

add_heading(doc, "安全边界")
add_body(doc, "本刷机包只刷写 boot、init boot、vendor boot、dtbo、vbmeta、vbmeta system、vbmeta vendor 和 super。")
add_body(doc, "明确禁止刷写或擦除 modem、md1img、persist、nvdata、nvcfg、nvram、protect f、protect s、preloader、lk、md sec、seccfg、proinfo 和 boot para。")
add_body(doc, "全新刷入和格式化仍然具有数据风险。重要资料必须提前备份，刷写失败时应保留完整报错和 logs 目录，不要盲目反复刷写。")

add_heading(doc, "已知限制与说明")
add_bullet(doc, "Stage48 的实机结论是保数据刷入、正常启动以及游戏场景进入和释放通过，不代表所有 ColorOS 私有硬件能力均已完成适配。")
add_bullet(doc, "相机、指纹、人脸、钱包与 eID、充电协议显示、AOD 和部分厂商增强能力，不在本次 Stage48 验收结论中标记为完整修复。")
add_bullet(doc, "完整首刷流程尚未在本轮重新进行一次从小米系统开始的全链路实机验收；首次跨系统刷入应预留回滚条件。")
add_bullet(doc, "Windows 7 和 Windows 10 兼容性来自旧版 API、PowerShell 2.0 语法边界和模拟分支验证，不等同于覆盖所有实体电脑和 USB 驱动组合。")
add_bullet(doc, "性能频率会受环境温度、电池状态、负载类型和小米底层温控共同影响，4.21 GHz 是低温实测峰值，不是所有场景的持续保证值。")

add_heading(doc, "文件校验")
hash_rows = [
    ("super.img SHA 256", "C87222305212FFD89A4A8E2E691708E010A622469BFCEDD013F95E096984B18A"),
    ("一键 EXE SHA 256", "1FCBA459124F5AFD33B4E70894D140E8C9E4EABB1164F68705CBFA1B8896E39A"),
    ("完整外层压缩包 SHA 256", "44341398C1DC730C59FEC8D4ACAFDDCBD8DDA497FA8D9AC8E650FD9740180F2E"),
]
htable = doc.add_table(rows=1, cols=2)
htable.alignment = WD_TABLE_ALIGNMENT.CENTER
htable.autofit = False
htable.columns[0].width = Inches(1.85)
htable.columns[1].width = Inches(4.95)
htable.rows[0].cells[0].text = "文件"
htable.rows[0].cells[1].text = "SHA 256"
for c in htable.rows[0].cells:
    shade_cell(c, "374151")
    set_cell_margins(c)
    for p in c.paragraphs:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for run in p.runs:
            set_run_font(run, size=10, bold=True, color="FFFFFF")
for idx, (key, value) in enumerate(hash_rows):
    cells = htable.add_row().cells
    cells[0].text = key
    cells[1].text = value
    if idx % 2:
        shade_cell(cells[0], "F5F7FA")
        shade_cell(cells[1], "F5F7FA")
    for ci, c in enumerate(cells):
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(c)
        for p in c.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if ci == 0 else WD_ALIGN_PARAGRAPH.LEFT
            for run in p.runs:
                set_run_font(run, name="Consolas" if ci == 1 else "Microsoft YaHei", size=8.5 if ci == 1 else 10, bold=(ci == 0))
set_table_borders(htable)

add_heading(doc, "发布信息")
add_body(doc, "作者：哆啦A梦")
add_body(doc, "请勿拆分、改名或遗漏发布包中的 EXE、K90 UPDATE 和 5 个 K90 PAYLOAD 分卷。转发时建议同时保留本说明和 SHA 256 校验信息。")

footer = section.footer
fp = footer.paragraphs[0]
fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
fr = fp.add_run("K90 Max ColorOS 17 Stage48  发布说明")
set_run_font(fr, size=8.5, color="777777")

doc.core_properties.title = "Redmi K90 Max ColorOS 17 Stage48 移植刷机包"
doc.core_properties.subject = "正式发布说明与刷机须知"
doc.core_properties.author = "哆啦A梦"
doc.core_properties.keywords = "Redmi K90 Max, ColorOS 17, Stage48, fastbootd"

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
doc.save(OUTPUT)
print(str(OUTPUT))
