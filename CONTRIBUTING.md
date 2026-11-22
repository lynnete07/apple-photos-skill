# Contributing / 参与贡献

Contributions are welcome when they preserve the project's safety model and low-decision workflow.

欢迎提交改进，但必须保持本项目的安全门禁与低决策负担设计。

## Rules

- Never include real Photos local identifiers, personal paths, GPS data, or private media metadata.
- Use synthetic album names and fixtures.
- Keep public defaults loss-averse: preserve sources, RAW files, and complete Live Photo pairs.
- Add no destructive shortcut that bypasses dry-run, current counts, or post-action verification.
- Keep `SKILL.md` concise; place detailed guidance in `references/`.

## Local validation

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m py_compile apple-photos/scripts/*.py
bash -n apple-photos/scripts/install.sh apple-photos/scripts/apple-photos
bash apple-photos/scripts/install.sh
apple-photos/scripts/apple-photos validate-manifest --manifest tests/valid_archive_manifest.json
```

The invalid manifest fixture must fail validation.

提交前请确认虚构样例、Python 测试、Shell 语法、Swift 编译和 manifest 校验全部通过。
