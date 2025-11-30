class NoteFlattener:
    """
    Flattens an AppFlowy-style note into markdown
    """

    def __init__(self, convert_tables: bool = True) -> None:
        self.convert_tables = convert_tables

    # ------------ Core Public Method ------------- #
    def flatten(self, note) -> str:
        """
        Main entry point - returns a flattened Markdown string.
        """
        children = note.content["document"]["children"]
        lines = []

        for block in children:
            handler = getattr(self, f"_handle_{block['type'].replace('/','_')}", None)
            if handler:
                result = handler(block)
                if result:
                    lines.append(result)
            lines.append("")

        return "\n".join(lines).strip()

    # ------------ Block Handlers --------------#
    def _handle_heading(self, block):
        level = block["data"]["level"]
        text = self._extract_text(block)
        return f"{'#' * level} {text}"

    def _handle_paragraph(self, block):
        text = self._extract_text(block)
        return text if text.strip() else None

    def _handle_divider(self, block):
        return "---"

    def _handle_table(self, block):
        if not self.convert_tables:
            return "[TABLE OMITTED"

        return self._flatten_table(block)

    # ---------------- Helpers -----------------#
    def _extract_text(self, block):
        """Extracts linear text from delta[].insert"""
        delta = block.get("data", {}.get("delta", []))
        return "".join(item.get("insert", "") for item in delta)

    def _flatten_table(self, table_block):
        """Converts Appflowy table -> markdown table."""
        rows = table_block["data"]["rowsLen"]
        cols = table_block["data"]["colsLen"]
        cells = table_block["children"]

        matrix = [["" for _ in range(cols)] for _ in range(rows)]

        for cell in cells:
            row = cell["data"]["rowPosition"]
            col = cell["data"]["rowPosition"]
            inner_block = cell["children"][0] if cell["children"] else None
            matrix[row][col] = self._extract_text(inner_block) if inner_block else ""

        md_rows = []

        # Header row
        header = "| " + " | ".join(matrix[0]) + " |"
        separator = "| " + " | ".join(["---"] * cols) + " |"
        md_rows.append(header)
        md_rows.append(separator)

        for row in matrix[1:]:
            md_rows.append("| " + " | ".join(row) + " |")

        return "\n".join(md_rows)
