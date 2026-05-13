# Issue Templates

Use the appropriate template based on the classification from Step 1. Replace all `{placeholders}` with interview answers. Remove any sections that don't apply.

---

## Bug Template

```markdown
> *Filed via QA report interview.*

## Summary

{one_sentence_summary}

## Expected Behaviour

{expected_behaviour}

## Actual Behaviour

{actual_behaviour}

## Steps to Reproduce

{numbered_step_list}

## Test Data Used

{specific_values_usernames_ids_payloads}

## Frequency

{every_time_or_intermittent_with_pattern}

## Error Output

```
{error_messages_stack_traces_console_output}
```

## Workaround

{workaround_or_none}

## Evidence

{attached_screenshots_videos_or_none}

## Impact

{who_is_affected_and_severity}

## Environment

- **OS**: {os_version}
- **Branch**: {git_branch} (`{short_sha}`)
- **Runtime**: {dotnet_node_version}
- **Environment**: {dev_staging_prod}

## Codebase Context

{summary_of_related_modules_recent_changes_test_coverage_gaps}

## Severity / Priority

- **Severity**: {severity_label}
- **Priority**: {priority_label}
```

---

## Feature Misalignment Template

```markdown
> *Filed via QA report interview.*

## Summary

{one_sentence_summary}

## Specification Reference

{link_to_spec_prd_design_or_description_of_expectation}

## Current Behaviour

{what_system_currently_does}

## Expected Behaviour (per spec)

{what_system_should_do}

## Steps to Observe

{numbered_step_list}

## Test Data Used

{specific_values_usernames_ids_payloads}

## Scope of Divergence

{single_field_vs_whole_workflow_and_related_areas}

## Evidence

{screenshots_comparing_expected_vs_actual_or_none}

## Impact

{blocking_release_failing_acceptance_or_nice_to_have}

## Environment

- **OS**: {os_version}
- **Branch**: {git_branch} (`{short_sha}`)
- **Runtime**: {dotnet_node_version}
- **Environment**: {dev_staging_prod}

## Codebase Context

{summary_of_related_modules_recent_changes_test_coverage_gaps}

## Severity / Priority

- **Severity**: {severity_label}
- **Priority**: {priority_label}
```
