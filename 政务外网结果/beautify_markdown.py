import re
import os

TARGET_HEADERS = {"标准要求", "当前状态", "备注"}
BOLD_STANDARD_KEYWORDS = [
    "KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准",
    "GB/T 22239-2019信息安全技术 网络安全等级保护基本要求",
    "JR/T 0068-2020网上银行系统信息安全通用规范",
    "GB/T 35273-2020个人信息安全规范"
]

# 分割单元格内的换行符：支持 <br> 或真实换行
SPLIT_PAT = re.compile(r'(?:<br\s*/?>|\r?\n)', flags=re.IGNORECASE)


def clean_bold_markers(text):
    """清理文本中多余的加粗标记"""
    # 处理重复的加粗标记
    text = re.sub(r'\*\*\*\*', '**', text)
    # 确保加粗标记成对出现
    text = re.sub(r'\*\*\s*\*\*', '', text)
    # 移除单个加粗标记
    text = re.sub(r'(?<!\*)\*(?!\*)', '', text)
    return text


def bold_security_standards(text):
    """将安全标准名称加粗"""
    for standard in BOLD_STANDARD_KEYWORDS:
        # 确保只在未加粗的地方添加加粗标记
        if standard in text and f"**{standard}**" not in text:
            text = text.replace(standard, f"**{standard}**")
    return text


def is_table_separator(line):
    """检查是否为表格分隔线"""
    return bool(re.match(r'^\s*\|(?:\s*:?-+:?\s*\|)+\s*$', line))


def split_table_row(row, expected_cols):
    """分割表格行，确保列数一致"""
    parts = [c for c in re.split(r'(?<!\\)\|', row.strip())[1:-1]]
    parts = [p.strip() for p in parts]
    if len(parts) < expected_cols:
        parts += [''] * (expected_cols - len(parts))
    elif len(parts) > expected_cols:
        parts = parts[:expected_cols]
    return parts


def bold_header_and_center(separator_count):
    """生成表头下方的分隔线，使用居中格式"""
    return "| " + " | ".join([":---:"] * separator_count) + " |"


def process_cell_content(text, is_target_column):
    """处理单元格内容，对目标列进行特殊处理"""
    if text is None:
        return ""
    raw = str(text).strip()
    # 对关键标准加粗
    for kw in BOLD_STANDARD_KEYWORDS:
        if kw in raw and f"**{kw}**" not in raw:
            raw = raw.replace(kw, f"**{kw}**")
    return raw


def process_file(file_path):
    """处理单个Markdown文件，确保表头居中和正确的表格边框格式"""
    try:
        # 读取文件内容
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        lines = content.splitlines()
        out_lines = []
        i = 0
        
        while i < len(lines):
            line = lines[i]
            
            # 检查是否为表格的开始行
            if '|' in line.strip():
                # 开始处理表格
                table_start = i
                # 尝试找到表格的所有行
                while i < len(lines) and '|' in lines[i].strip():
                    i += 1
                table_end = i
                
                # 提取表格所有行
                table_lines = lines[table_start:table_end]
                
                # 解析表格
                if len(table_lines) >= 1:
                    # 获取表头和数据
                    header_line = table_lines[0]
                    
                    # 分割表头单元格
                    raw_headers = [h.strip() for h in header_line.strip().strip('|').split('|')]
                    col_count = len(raw_headers)
                    
                    # 表头加粗
                    bolded_headers = [f"**{h}**" for h in raw_headers]
                    out_lines.append("| " + " | ".join(bolded_headers) + " |")
                    
                    # 使用居中分隔线确保表头居中显示
                    out_lines.append("| " + " | ".join([":---:"] * col_count) + " |")
                    
                    # 处理数据行
                    for data_line in table_lines[1:]:
                        # 跳过分隔线（如果有）
                        if is_table_separator(data_line):
                            continue
                        
                        # 分割数据单元格
                        cells = [cell.strip() for cell in data_line.strip().strip('|').split('|')]
                        
                        # 确保列数一致
                        while len(cells) < col_count:
                            cells.append('')
                        
                        # 对关键标准加粗
                        for j, cell in enumerate(cells):
                            for kw in BOLD_STANDARD_KEYWORDS:
                                if kw in cell and f"**{kw}**" not in cell:
                                    cells[j] = cell.replace(kw, f"**{kw}**")
                        
                        # 确保正确的边框格式
                        out_lines.append("| " + " | ".join(cells) + " |")
            else:
                # 非表格行：加粗关键短语
                s = line
                for kw in BOLD_STANDARD_KEYWORDS:
                    if kw in s and f"**{kw}**" not in s:
                        s = s.replace(kw, f"**{kw}**")
                out_lines.append(s)
                i += 1
        
        # 重新组合内容
        processed_content = '\n'.join(out_lines)
        
        # 清理多余的加粗标记
        processed_content = clean_bold_markers(processed_content)
        
        # 写回文件
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(processed_content)
        
        print(f"已处理文件: {os.path.basename(file_path)}")
        return True
    except Exception as e:
        print(f"处理文件 {file_path} 时出错: {e}")
        return False


def main():
    """主函数"""
    # 获取当前目录下所有的Markdown文件
    md_files = [f for f in os.listdir('.') if f.endswith('.md')]
    
    if not md_files:
        print("没有找到Markdown文件")
        return
    
    print(f"找到 {len(md_files)} 个Markdown文件")
    
    success_count = 0
    for md_file in sorted(md_files):
        file_path = os.path.join('.', md_file)
        if process_file(file_path):
            success_count += 1
    
    print(f"所有文件处理完成! 成功处理 {success_count} 个文件")

if __name__ == "__main__":
    main()