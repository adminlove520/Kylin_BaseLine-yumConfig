with open('10.58.37.50_baseline_20251004.md', 'r', encoding='utf-8') as f:
    content = f.read(1000)
    lines = content.split('\n')
    for i, line in enumerate(lines[:20]):
        print(f"Line {i+1}: {repr(line.strip())}")