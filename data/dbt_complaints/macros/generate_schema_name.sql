{#- Use the schema names from dbt_project.yml exactly (stg, int, marts, seeds)
    instead of dbt's default "main_stg". Keeps them apart from Day 6's silver/gold schemas. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
