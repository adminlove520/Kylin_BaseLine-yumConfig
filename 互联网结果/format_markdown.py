import re
import sys
from pathlib import Path
from html import escape

TARGET_HEADERS = {"标准要求", "当前状态", "备注"}
BOLD_STANDARD_KEYWORDS = [
    "KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准",
    "YD/T 2701-2014 附录A",
    "YD/T 2701-2014 6.2.1账户安全要求",
]

# 分割单元格内的换行符：支持 <br> 或真实换行
SPLIT_PAT = re.compile(r'(?:<br\s*/?>|\r?\n)', flags=re.IGNORECASE)
NUM_ITEM_RE = re.compile(r'^\s*\d+\.')
COMMA_PAT = re.compile(r'[，,]')
SEMICOLON_PAT = re.compile(r'[；;]')

def merge_trailing_comma(parts):
    """
    将以逗号结尾的行与下一行合并（去掉结尾逗号），例如:
      ['adm,', '已禁用', 'lp,', '已禁用'] -> ['adm 已禁用', 'lp 已禁用']
    以避免之后按逗号分割时把续行拆开。
    """
    if not parts:
        return parts
    out = []
    i = 0
    while i < len(parts):
        cur = parts[i].rstrip()
        # 合并连续以逗号结尾的片段（支持中文逗号）
        while cur.endswith(',') or cur.endswith('，'):
            cur = cur[:-1].rstrip()  # 去掉结尾逗号
            i += 1
            if i < len(parts):
                cur = cur + " " + parts[i].strip()
            else:
                break
        out.append(cur.strip())
        i += 1
    return out

def expand_by_comma_semicolon(parts):
    """
    扩展 parts：
    - 优先按分号分割（分号项标记为标题项，保留结尾分号标记）。
    - 否则按逗号分割为多个条目。
    - 处理单行内只有逗号情况（"a,b,c,d" -> ['a','b','c','d']）。
    """
    out = []
    for p in parts:
        if not p:
            continue
        # 先按分号拆分并标记
        if SEMICOLON_PAT.search(p):
            segs = [s.strip() for s in SEMICOLON_PAT.split(p) if s.strip()]
            for s in segs:
                out.append(s + ";")
            continue
        # 再按逗号拆分（处理连续逗号、末尾逗号）
        if COMMA_PAT.search(p):
            segs = [s.strip() for s in COMMA_PAT.split(p) if s.strip()]
            out.extend(segs)
            continue
        out.append(p.strip())
    return out

def split_chinese_colon_parts(parts):
    """
    如果某一行以中文冒号 '：' 分隔且该行本身不含逗号/分号（即可能是 name：code：value 或 name：value），
    则把该行拆成多个独立元素，方便后续按三元/二元组合并为有序项。
    已有序号开头（如 '1.'）的行保留原样。
    """
    out = []
    for p in parts:
        if not p:
            continue
        if NUM_ITEM_RE.match(p):
            out.append(p)
            continue
        # 仅在不包含逗号或分号时按中文冒号拆分，避免误伤带说明的长句
        if '：' in p and not COMMA_PAT.search(p) and not SEMICOLON_PAT.search(p):
            segs = [s.strip() for s in p.split('：') if s.strip()]
            if len(segs) >= 2:
                out.extend(segs)
                continue
        out.append(p)
    return out

def compact_to_ordered_list_lines(lines):
    """把若干行合并为有序列表项，优先三元组 (name, code, value)，否则两元组 (name, value)。
    特殊处理：
      - 已有数字序号行（如 '1.xxx'）直接保留。
      - 以分号结尾的行视作“标题/仅名”条目，直接生成序号项（不再尝试取 code/value）。
      - lines 已经经过 expand_by_comma_semicolon 和 split_chinese_colon_parts 的预处理（可包含由逗号拆分的多项和分号标记）。
    """
    if not lines:
        return []
    items = []
    i = 0
    idx = 1
    while i < len(lines):
        cur = lines[i].strip()
        # 若行本身已有序号，直接保留（不重新编号）
        if NUM_ITEM_RE.match(cur):
            items.append(cur)
            i += 1
            continue
        # 分号结尾视作标题/仅名
        if cur.endswith(";"):
            items.append(f"{idx}.{cur[:-1].strip()}")
            i += 1
            idx += 1
            continue
        # 尝试三元组：name, code, value
        if i + 2 < len(lines):
            a = lines[i].strip()
            b = lines[i + 1].strip()
            c = lines[i + 2].strip()
            # 若中间行像代码（大写或包含下划线/数字）且不含汉字，则认为是code
            if (re.search(r'[A-Z0-9_]', b) and not re.search(r'[\u4e00-\u9fff]', b)):
                items.append(f"{idx}.{a}：{b}：{c}")
                i += 3
            else:
                # 否则尝试两行一组 (name, value)
                items.append(f"{idx}.{a}：{b}")
                i += 2
        elif i + 1 < len(lines):
            a = lines[i].strip()
            b = lines[i + 1].strip()
            items.append(f"{idx}.{a}：{b}")
            i += 2
        else:
            items.append(f"{idx}.{lines[i].strip()}")
            i += 1
        idx += 1
    return items

def process_cell_content(text, is_target_column):
    """处理单元格文本：目标列尝试合并为有序列表并用 <br> 分隔；同时对关键标准加粗（Markdown **）。
    支持逗号分隔多项、分号作为标题标记；当一行以逗号结尾时会与下一行合并再处理。
    同时对含中文冒号 '：' 的行进行智能拆分，避免冒号影响逗号/有序列表合并。
    """
    if text is None:
        return ""
    raw = str(text).strip()
    parts = [p for p in SPLIT_PAT.split(raw) if p.strip()]
    if not parts:
        return ""
    # 先合并以逗号结尾的行和下一行，避免被后续逗号分割拆开
    parts = merge_trailing_comma(parts)

    # 如果只有一行且包含逗号，则直接把该行按逗号拆成多个 parts（但此处已经合并了结尾逗号场景）
    if len(parts) == 1 and COMMA_PAT.search(parts[0]) and not SEMICOLON_PAT.search(parts[0]):
        parts = [s.strip() for s in COMMA_PAT.split(parts[0]) if s.strip()]
    else:
        # 否则按既有逻辑扩展（分号->标题标记，逗号->拆分）
        parts = expand_by_comma_semicolon(parts)

    # 针对包含中文冒号的行进行拆分（如 "密码有效期：PASS_MAX_DAYS：90天"）以便生成有序项
    parts = split_chinese_colon_parts(parts)

    if is_target_column and parts:
        items = compact_to_ordered_list_lines(parts)
        if items:
            joined = "<br>".join(items)
            for kw in BOLD_STANDARD_KEYWORDS:
                if kw in joined:
                    joined = joined.replace(kw, f"**{kw}**")
            return joined
    # 非目标列或未合成：规范 <br> 并加粗关键短语
    s = re.sub(r'<br\s*/?>', '<br>', raw, flags=re.IGNORECASE)
    for kw in BOLD_STANDARD_KEYWORDS:
        if kw in s:
            s = s.replace(kw, f"**{kw}**")
    return s

def bold_header_and_center(separator_count):
    return "| " + " | ".join([":---:"] * separator_count) + " |"

def is_table_separator(line):
    return bool(re.match(r'^\s*\|(?:\s*:?-+:?\s*\|)+\s*$', line))

def split_table_row(row, expected_cols):
    parts = [c for c in re.split(r'(?<!\\)\|', row.strip())[1:-1]]
    parts = [p.strip() for p in parts]
    if len(parts) < expected_cols:
        parts += [''] * (expected_cols - len(parts))
    elif len(parts) > expected_cols:
        parts = parts[:expected_cols]
    return parts

def process_markdown_tables(md_text):
    """处理 md 文本返回处理后的 md（表头加粗居中，目标列合并为有序项并用 <br> 分隔，关键标准加粗）"""
    lines = md_text.splitlines()
    out_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith("|") and i + 1 < len(lines) and is_table_separator(lines[i+1]):
            header_line = lines[i]
            raw_headers = [h.strip() for h in header_line.strip().strip('|').split('|')]
            col_count = len(raw_headers)
            header_names = [h for h in raw_headers]
            bolded_headers = [f"**{h}**" if h else h for h in raw_headers]
            out_lines.append("| " + " | ".join(bolded_headers) + " |")
            out_lines.append(bold_header_and_center(col_count))
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                row = lines[i]
                cells = split_table_row(row, col_count)
                target_indexes = {idx for idx, name in enumerate(header_names) if name in TARGET_HEADERS}
                new_cells = []
                for idx, cell in enumerate(cells):
                    is_target = idx in target_indexes
                    new_cell = process_cell_content(cell, is_target)
                    # 最后确保关键短语加粗
                    for kw in BOLD_STANDARD_KEYWORDS:
                        if kw in new_cell:
                            new_cell = new_cell.replace(kw, f"**{kw}**")
                    new_cells.append(" " + new_cell + " ")
                out_lines.append("|" + "|".join(new_cells) + "|")
                i += 1
            continue
        # 非表格行：加粗关键短语
        s = line
        for kw in BOLD_STANDARD_KEYWORDS:
            if kw in s:
                s = s.replace(kw, f"**{kw}**")
        out_lines.append(s)
        i += 1
    return "\n".join(out_lines)

def md_table_to_html(processed_md):
    """把处理后的 Markdown 表格转换为简单可自适应的 HTML（用于浏览器查看以获得自适应列宽/行高）。
    改进：
      - 增强边框和表头样式，添加隔行背景；
      - 根据列最长文本计算宽度并增大最小宽度与留白（ch 单位），限制最大宽度，保证显示美观；
      - 有序列表保持 inline 不换行以尽量显示于一行。
    """
    lines = processed_md.splitlines()
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith("|") and i + 1 < len(lines) and is_table_separator(lines[i+1]):
            raw_headers = [h.strip() for h in lines[i].strip().strip('|').split('|')]
            col_count = len(raw_headers)
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = split_table_row(lines[i], col_count)
                rows.append(cells)
                i += 1
            # compute max chars per column
            max_chars = [0] * col_count
            for r in rows:
                for ci, cell in enumerate(r):
                    parts = [p for p in cell.split("<br>") if p.strip()]
                    if not parts:
                        length = 0
                    else:
                        length = max(len(re.sub(r'\*\*', '', p)) for p in parts)
                    if length > max_chars[ci]:
                        max_chars[ci] = length
            # build table HTML using computed widths
            css = """
    <style>
      body { font-family: "Segoe UI", Tahoma, Arial, "Microsoft Yahei", sans-serif; color:#222; }
      table { border-collapse: separate; border-spacing: 0; width: 100%; table-layout: fixed; }
      col { vertical-align: top; }
      th, td { border: 1px solid #999; padding: 10px 12px; vertical-align: top; text-align: left; box-sizing: border-box; }
      th { text-align: center; font-weight: 700; background: #f3f6fb; color: #111; }
      tbody tr:nth-child(even) td { background: #fbfbfb; }
      td { white-space: normal; word-break: break-word; }
      ol.inline-list { margin: 0; padding-left: 1.2em; white-space: nowrap; display: inline-block; }
      /* 保证有序列表项之间间距合理 */
      ol.inline-list li { display: inline; margin-right: 0.8em; }
    </style>
    """
            out.append("<!doctype html><html><head><meta charset='utf-8'/>" + css + "</head><body>")
            out.append("<table>")
            # colgroup: 以 ch 为单位设置宽度，增加最小宽和留白，限制最大宽度
            col_styles = []
            for mc in max_chars:
                # 最小宽度 14ch，留白 +8，最大宽度 120ch
                width_ch = min(max(14, mc + 8), 120)
                col_styles.append(f"<col style='width:{width_ch}ch'/>")
            out.append("<colgroup>" + "".join(col_styles) + "</colgroup>")
            out.append("<thead><tr>" + "".join(f"<th>{escape(h.replace('**',''))}</th>" for h in raw_headers) + "</tr></thead>")
            out.append("<tbody>")
            for r in rows:
                tds = []
                for c in r:
                    c2 = c.replace("<br>", "\n")
                    parts = [p.strip() for p in c2.splitlines() if p.strip()]
                    if parts and all(NUM_ITEM_RE.match(p) for p in parts):
                        lis = "".join(f"<li>{escape(re.sub(r'^\s*\\d+\\.\\s*','',p))}</li>" for p in parts)
                        html = f"<ol class='inline-list'>{lis}</ol>"
                    else:
                        tmp = escape(c2).replace("**", "")
                        tmp = tmp.replace("\n", "<br>")
                        html = tmp
                    tds.append(f"<td>{html}</td>")
                out.append("<tr>" + "".join(tds) + "</tr>")
            out.append("</tbody></table><br/>")
            out.append("</body></html>")
        else:
            out.append("<p>" + escape(line).replace("**","<strong>").replace("<strong>", "<strong>").replace("</strong>", "</strong>") + "</p>")
            i += 1
    return "\n".join(out)

def main(inpath=None, outpath=None, html=False):
    """
    - 不传参数：处理脚本所在目录下所有 .md（覆盖）。
    - 传入文件或目录：处理目标。
    - --html True 时：为每个 .md 生成同名 .html（或指定输出目录下）。
    """
    if inpath:
        p = Path(inpath)
        if p.is_dir():
            md_files = sorted(p.glob('*.md'))
            if not md_files:
                print("目标目录下无 .md 文件:", p)
                return 1
        elif p.exists():
            md_files = [p]
        else:
            print("输入文件/目录不存在:", inpath)
            return 1
    else:
        script_dir = Path(__file__).parent
        md_files = sorted(script_dir.glob('*.md'))
        if not md_files:
            print("脚本目录下无 .md 文件:", script_dir)
            return 1

    outpath_p = Path(outpath) if outpath else None
    for md in md_files:
        txt = md.read_text(encoding='utf-8')
        newtxt = process_markdown_tables(txt)
        # 写回 markdown（覆盖或到指定目的）
        if outpath_p:
            if outpath_p.exists() and outpath_p.is_dir():
                out_file = outpath_p / md.name
            else:
                if len(md_files) == 1:
                    out_file = outpath_p
                else:
                    outpath_p.mkdir(parents=True, exist_ok=True)
                    out_file = outpath_p / md.name
        else:
            out_file = md
        out_file.write_text(newtxt, encoding='utf-8')
        print("已保存 markdown:", out_file)
        # 若需要 html 输出
        if html:
            html_text = md_table_to_html(newtxt)
            html_out = (out_file.with_suffix('.html') if out_file.suffix == '.md' else out_file.with_suffix('.html'))
            html_out.write_text(html_text, encoding='utf-8')
            print("已生成 HTML:", html_out)
    return 0

if __name__ == "__main__":
    # 用法：
    # 无参数：处理脚本目录下所有 md，覆盖
    # 处理指定目录或文件： format_markdown.py path [outpath]
    # 指定 --html 输出 html（可放到 outpath 目录）
    args = sys.argv[1:]
    html_flag = False
    if "--html" in args:
        html_flag = True
        args.remove("--html")
    if len(args) == 0:
        sys.exit(main(None, None, html=html_flag))
    elif len(args) == 1:
        sys.exit(main(args[0], None, html=html_flag))
    else:
        sys.exit(main(args[0], args[1], html=html_flag))