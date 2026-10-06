{#- Remove legal-form suffixes from the END of a cleaned company name, `passes` times.
    One pass cannot remove two neighbouring suffixes ("CORP INC"), so we repeat it.
    Only the end of the name is touched: "CREDIT CORP SOLUTIONS" keeps its CORP. -#}
{% macro strip_legal_suffixes(expr, passes=3) -%}
    {%- set suffixes = "(INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)" -%}
    {%- set ns = namespace(sql=expr) -%}
    {%- for i in range(passes) -%}
        {%- set ns.sql = "regexp_replace(" ~ ns.sql ~ ", ' " ~ suffixes ~ "$', '')" -%}
    {%- endfor -%}
    {{ ns.sql }}
{%- endmacro %}
