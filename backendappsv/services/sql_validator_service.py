import re

class SQLValidatorService:

    def validate(self, sql):

        sql_clean = sql.strip().lower()

        if not sql_clean.startswith("select"):
            return False

        forbidden_keywords = [
            r"\bdrop\b",
            r"\bdelete\b",
            r"\bupdate\b",
            r"\binsert\b",
            r"\balter\b",
            r"\btruncate\b"
        ]

        for pattern in forbidden_keywords:
            if re.search(pattern, sql_clean):
                return False

        return True