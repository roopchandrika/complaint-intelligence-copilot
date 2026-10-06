{#- Upper case, drop apostrophes (IPAC'S -> IPACS), other punctuation -> space,
    collapse spaces, drop a leading "THE". -#}
{% macro clean_company_text(col) -%}
    trim(regexp_replace(
        trim(regexp_replace(regexp_replace(regexp_replace(upper({{ col }}), '[''`]', '', 'g'),
                                           '[.,&"()/]', ' ', 'g'), '\s+', ' ', 'g')),
        '^THE ', ''))
{%- endmacro %}
