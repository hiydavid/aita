"""Generate the deterministic Aita synthetic HR landing datasets."""

from __future__ import annotations

import argparse
import re
from datetime import date
from pathlib import PurePosixPath

import pandas as pd
from pyspark.sql import Column, DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType


DEFAULT_PROFILE = "genie-workbench"
DEFAULT_CATALOG = "genie_workbench_dev_catalog"
DEFAULT_BRONZE_SCHEMA = "aita_bronze"
DEFAULT_LANDING_PATH = "/Volumes/genie_workbench_dev_catalog/aita_bronze/landing"
DEFAULT_SEED = 20261024
DEFAULT_WORKER_COUNT = 20_000
HISTORY_START = date(2024, 10, 1)
AS_OF_DATE = date(2026, 9, 30)
ORG_UNIT_COUNT = 72
JOB_COUNT = 60
REQUISITION_COUNT = 2_400
APPLICATIONS_PER_REQUISITION = 12

BUSINESS_LINES = [
    "Consumer Banking",
    "Wealth Management",
    "Commercial Banking",
    "Operations",
    "Technology",
    "Corporate Functions",
]

JOB_PREFIXES = ["CON", "WEA", "COM", "OPS", "TEC", "COR"]

JOB_TITLES = [
    "Contact Center Representative",
    "Senior Contact Center Representative",
    "Branch Banker",
    "Universal Banker",
    "Customer Service Lead",
    "Branch Operations Manager",
    "Regional Service Manager",
    "Consumer Lending Specialist",
    "Mortgage Loan Originator",
    "Consumer Banking Director",
    "Financial Advisor",
    "Senior Financial Advisor",
    "Private Wealth Advisor",
    "Client Service Associate",
    "Portfolio Analyst",
    "Trust Specialist",
    "Wealth Operations Manager",
    "Investment Strategist",
    "Regional Wealth Manager",
    "Wealth Management Director",
    "Relationship Associate",
    "Relationship Manager",
    "Senior Relationship Manager",
    "Credit Analyst",
    "Portfolio Manager",
    "Treasury Solutions Consultant",
    "Commercial Underwriter",
    "Market Executive",
    "Commercial Strategy Lead",
    "Commercial Banking Director",
    "Operations Processor",
    "KYC Operations Analyst",
    "Fraud Operations Analyst",
    "Fraud Investigator",
    "Payments Operations Specialist",
    "Operations Quality Lead",
    "Operations Manager",
    "Automation Product Owner",
    "Operational Risk Strategist",
    "Operations Director",
    "Data Scientist",
    "Machine Learning Engineer",
    "Data Engineer",
    "AI Product Manager",
    "Software Engineer",
    "Cloud Platform Engineer",
    "Cybersecurity Analyst",
    "Technology Program Manager",
    "Enterprise Architect",
    "Technology Director",
    "Financial Analyst",
    "HR Business Partner",
    "Talent Acquisition Partner",
    "Compliance Analyst",
    "Legal Counsel",
    "Risk Manager",
    "Learning Program Manager",
    "Communications Manager",
    "Corporate Strategy Lead",
    "Corporate Functions Director",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default=DEFAULT_PROFILE)
    parser.add_argument("--catalog", default=DEFAULT_CATALOG)
    parser.add_argument("--bronze-schema", default=DEFAULT_BRONZE_SCHEMA)
    parser.add_argument("--landing-path", default=DEFAULT_LANDING_PATH)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--worker-count", type=int, default=DEFAULT_WORKER_COUNT)
    return parser.parse_args()


def validate_identifier(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise ValueError(f"Invalid Unity Catalog identifier: {value}")
    return value


def volume_name_from_path(landing_path: str, catalog: str, schema: str) -> str:
    parts = PurePosixPath(landing_path).parts
    if len(parts) != 5 or parts[:2] != ("/", "Volumes"):
        raise ValueError("landing_path must be a Unity Catalog volume root")
    if parts[2] != catalog or parts[3] != schema:
        raise ValueError("landing_path catalog and schema must match the arguments")
    return validate_identifier(parts[4])


def literal_array(values: list[str]) -> Column:
    return F.array(*[F.lit(value) for value in values])


def array_item(values: list[str], zero_based_index: Column) -> Column:
    return F.element_at(literal_array(values), zero_based_index.cast("int") + F.lit(1))


def stable_mod(seed: int, modulus: int, salt: int, *columns: Column) -> Column:
    return F.pmod(F.xxhash64(*columns, F.lit(seed + salt)), F.lit(modulus)).cast("long")


def stable_fraction(seed: int, salt: int, *columns: Column) -> Column:
    return stable_mod(seed, 10_000, salt, *columns).cast("double") / F.lit(10_000.0)


PERSON_SCHEMA = StructType(
    [StructField("first_name", StringType()), StructField("last_name", StringType())]
)


@F.pandas_udf(PERSON_SCHEMA)
def fake_person(worker_indexes: pd.Series) -> pd.DataFrame:
    from faker import Faker

    first_names: list[str] = []
    last_names: list[str] = []
    for worker_index in worker_indexes:
        fake = Faker("en_US")
        fake.seed_instance(DEFAULT_SEED + int(worker_index))
        first_names.append(fake.first_name())
        last_names.append(fake.last_name())
    return pd.DataFrame({"first_name": first_names, "last_name": last_names})


def create_session(profile: str) -> SparkSession:
    active_session = SparkSession.getActiveSession()
    if active_session is not None:
        return active_session

    from databricks.connect import DatabricksEnv, DatabricksSession

    environment = DatabricksEnv().withDependencies("faker==37.12.0")
    return (
        DatabricksSession.builder.profile(profile)
        .serverless(True)
        .withEnvironment(environment)
        .getOrCreate()
    )


def build_jobs(spark: SparkSession) -> DataFrame:
    job_index = F.col("job_index")
    line_index = F.floor(job_index / F.lit(10)).cast("int")
    role_index = F.pmod(job_index, F.lit(10)).cast("int")
    job_title = array_item(JOB_TITLES, job_index)
    job_code = F.concat(
        array_item(JOB_PREFIXES, line_index),
        F.format_string("%02d", role_index + F.lit(1)),
    )
    licensed_role = ((line_index == 1) & (role_index <= 2)) | (
        (line_index == 0) & (role_index == 8)
    )
    strategic_role = ((line_index == 4) & (role_index <= 4)) | (
        (line_index == 3) & role_index.isin(7, 8)
    )
    genai_exposure = (
        F.when((line_index == 3) & (role_index <= 2), F.lit("high"))
        .when((line_index == 0) & (role_index <= 1), F.lit("high"))
        .when((line_index == 4) & (role_index <= 4), F.lit("medium"))
        .otherwise(F.lit("low"))
    )
    description = (
        F.when(
            (line_index == 3) & (role_index <= 2),
            F.concat(
                F.lit("Process high-volume banking operations using rules, document review, and repetitive case decisions. Generative AI and workflow automation can augment this "),
                F.lower(job_title),
                F.lit(" role; adjacent skills include SQL, data quality, controls, and customer judgment."),
            ),
        )
        .when(
            (line_index == 0) & (role_index <= 1),
            F.concat(
                F.lit("Resolve customer requests across phone and chat using scripted knowledge, summarization, and case routing. Generative AI can augment this "),
                F.lower(job_title),
                F.lit(" role while empathy and escalation judgment remain essential."),
            ),
        )
        .when(
            line_index == 4,
            F.concat(
                F.lit("Design and deliver secure banking technology as a "),
                F.lower(job_title),
                F.lit(" using data, cloud platforms, software engineering, AI governance, and measurable product outcomes."),
            ),
        )
        .when(
            licensed_role,
            F.concat(
                F.lit("Advise clients as a "),
                F.lower(job_title),
                F.lit(" while maintaining required licenses, fiduciary standards, relationship trust, and regulatory compliance."),
            ),
        )
        .otherwise(
            F.concat(
                F.lit("Deliver banking outcomes as a "),
                F.lower(job_title),
                F.lit(" through customer focus, risk discipline, collaboration, and continuous improvement."),
            )
        )
    )
    return (
        spark.range(JOB_COUNT, numPartitions=1)
        .withColumnRenamed("id", "job_index")
        .select(
            job_code.alias("job_code"),
            job_title.alias("job_title"),
            job_title.alias("job_family"),
            array_item(
                ["Entry", "Intermediate", "Senior", "Lead", "Manager", "Director"],
                F.least(F.floor(role_index / F.lit(2)).cast("int"), F.lit(5)),
            ).alias("job_level"),
            array_item(BUSINESS_LINES, line_index).alias("business_line"),
            licensed_role.alias("licensed_role_flag"),
            strategic_role.alias("strategic_role_flag"),
            genai_exposure.alias("expected_genai_exposure_tier"),
            description.alias("job_description"),
        )
    )


def build_org_units(spark: SparkSession) -> DataFrame:
    org_index = F.col("org_index")
    line_index = F.floor(org_index / F.lit(12)).cast("int")
    unit_index = F.pmod(org_index, F.lit(12)).cast("int")
    business_line = array_item(BUSINESS_LINES, line_index)
    special_name = (
        F.when(org_index == 0, F.lit("Phoenix Contact Center"))
        .when(org_index == 1, F.lit("Tampa Contact Center"))
        .when(org_index == 10, F.lit("Pacific Consumer Excellence"))
        .when(org_index == 11, F.lit("Northeast Consumer Excellence"))
        .when(org_index == 36, F.lit("Fraud Operations East"))
        .when(org_index == 37, F.lit("Fraud Operations West"))
        .when(org_index == 38, F.lit("Payments Service Excellence"))
        .otherwise(
            F.concat(
                business_line,
                F.lit(" Team "),
                F.format_string("%02d", unit_index + F.lit(1)),
            )
        )
    )
    org_type = (
        F.when(org_index.isin(0, 1), F.lit("Contact Center"))
        .when(org_index.isin(36, 37), F.lit("Fraud Operations"))
        .when(line_index == 0, F.lit("Branch Network"))
        .when(line_index == 4, F.lit("Technology Team"))
        .otherwise(F.lit("Business Team"))
    )
    return (
        spark.range(ORG_UNIT_COUNT, numPartitions=1)
        .withColumnRenamed("id", "org_index")
        .select(
            F.format_string("ORG%03d", org_index + F.lit(1)).alias("org_unit_id"),
            special_name.alias("org_unit_name"),
            business_line.alias("business_line"),
            org_type.alias("org_type"),
            array_item(
                ["West", "South", "Northeast", "Midwest"],
                F.pmod(unit_index, F.lit(4)).cast("int"),
            ).alias("region"),
            array_item(
                ["Phoenix", "Tampa", "New York", "Chicago", "Dallas", "San Francisco"],
                F.pmod(org_index, F.lit(6)).cast("int"),
            ).alias("location"),
            F.concat(F.lit("BL"), F.format_string("%02d", line_index + F.lit(1))).alias(
                "parent_org_unit_id"
            ),
            F.format_string("EMP%06d", org_index + F.lit(1)).alias("manager_id"),
            F.when(org_index.isin(0, 1), F.lit("2026-01-15").cast("date")).alias(
                "schedule_change_date"
            ),
            org_index.isin(10, 11, 38).alias("standout_manager_flag"),
        )
    )


def build_workers(spark: SparkSession, worker_count: int, seed: int) -> tuple[DataFrame, DataFrame]:
    worker_index = F.col("worker_index")
    org_index = F.pmod(worker_index, F.lit(ORG_UNIT_COUNT)).cast("int")
    line_index = F.floor(org_index / F.lit(12)).cast("int")
    ordinary_role_index = F.pmod(F.floor(worker_index / F.lit(ORG_UNIT_COUNT)), F.lit(10)).cast(
        "int"
    )
    role_index = (
        F.when(org_index.isin(0, 1), F.pmod(ordinary_role_index, F.lit(4)))
        .when(org_index.isin(36, 37), F.pmod(ordinary_role_index, F.lit(5)))
        .otherwise(ordinary_role_index)
        .cast("int")
    )
    worker_id = F.format_string("EMP%06d", worker_index + F.lit(1))
    org_unit_id = F.format_string("ORG%03d", org_index + F.lit(1))
    job_code = F.concat(
        array_item(JOB_PREFIXES, line_index), F.format_string("%02d", role_index + F.lit(1))
    )
    business_line = array_item(BUSINESS_LINES, line_index)
    manager_slot = F.pmod(
        F.floor(worker_index / F.lit(ORG_UNIT_COUNT)), F.lit(4)
    ).cast("long")
    manager_index = org_index.cast("long") + manager_slot * F.lit(ORG_UNIT_COUNT)
    manager_id = F.format_string("EMP%06d", manager_index + F.lit(1))
    hire_date = F.date_sub(
        F.lit(HISTORY_START),
        (stable_mod(seed, 5_110, 1, worker_index) + F.lit(365)).cast("int"),
    )
    target_manager = manager_id.isin("EMP000001", "EMP000073", "EMP000002")
    contact_center = org_index.isin(0, 1)
    standout_team = org_index.isin(10, 11, 38)
    exit_fraction = stable_fraction(seed, 2, worker_index)
    exits = (
        F.when(contact_center & target_manager, exit_fraction < F.lit(0.48))
        .when(contact_center, exit_fraction < F.lit(0.10))
        .when(standout_team, exit_fraction < F.lit(0.012))
        .otherwise(exit_fraction < F.lit(0.055))
    )
    planted_exit_date = F.date_add(
        F.lit("2026-02-01").cast("date"),
        stable_mod(seed, 120, 3, worker_index).cast("int"),
    )
    ordinary_exit_date = F.date_add(
        F.lit(HISTORY_START), stable_mod(seed, 700, 4, worker_index).cast("int")
    )
    termination_date = F.when(
        exits,
        F.when(contact_center & target_manager, planted_exit_date).otherwise(ordinary_exit_date),
    )
    strategic_technology = (line_index == 4) & (role_index <= 3)
    stalled_high_performer = strategic_technology & (
        stable_fraction(seed, 5, worker_index) < F.lit(0.35)
    )
    promotion_flag = (
        (stable_fraction(seed, 6, worker_index) < F.lit(0.18))
        & (role_index > 0)
        & ~stalled_high_performer
    )
    transfer_flag = stable_fraction(seed, 7, worker_index) < F.lit(0.12)
    manager_change_flag = stable_fraction(seed, 8, worker_index) < F.lit(0.10)
    workers_core = (
        spark.range(worker_count, numPartitions=8)
        .withColumnRenamed("id", "worker_index")
        .select(
            worker_index,
            worker_id.alias("worker_id"),
            org_index.alias("org_index"),
            org_unit_id.alias("org_unit_id"),
            line_index.alias("line_index"),
            business_line.alias("business_line"),
            role_index.alias("role_index"),
            job_code.alias("job_code"),
            manager_id.alias("manager_id"),
            hire_date.alias("hire_date"),
            termination_date.alias("termination_date"),
            target_manager.alias("target_manager_flag"),
            contact_center.alias("contact_center_flag"),
            org_index.isin(36, 37).alias("fraud_operations_flag"),
            standout_team.alias("standout_team_flag"),
            stalled_high_performer.alias("stalled_high_performer_flag"),
            promotion_flag.alias("promotion_flag"),
            transfer_flag.alias("transfer_flag"),
            manager_change_flag.alias("manager_change_flag"),
        )
    )
    workers_with_person = workers_core.withColumn("person", fake_person(F.col("worker_index")))
    workers = workers_with_person.select(
        "worker_id",
        F.col("person.first_name").alias("first_name"),
        F.col("person.last_name").alias("last_name"),
        F.lower(
            F.concat_ws(
                ".",
                F.regexp_replace(F.col("person.first_name"), "[^A-Za-z]", ""),
                F.regexp_replace(F.col("person.last_name"), "[^A-Za-z]", ""),
            )
        )
        .substr(F.lit(1), F.lit(48))
        .alias("email_local_part"),
        F.date_sub(
            F.col("hire_date"),
            (stable_mod(seed, 14_600, 9, F.col("worker_index")) + F.lit(6_570)).cast("int"),
        ).alias("birth_date"),
        array_item(
            ["Female", "Male", "Non-binary", "Prefer not to say"],
            F.when(stable_fraction(seed, 10, F.col("worker_index")) < 0.48, F.lit(0))
            .when(stable_fraction(seed, 10, F.col("worker_index")) < 0.94, F.lit(1))
            .when(stable_fraction(seed, 10, F.col("worker_index")) < 0.98, F.lit(2))
            .otherwise(F.lit(3)),
        ).alias("gender"),
        "hire_date",
        "termination_date",
        F.when(F.col("termination_date").isNull(), F.lit("Active"))
        .otherwise(F.lit("Terminated"))
        .alias("employment_status"),
        "job_code",
        "org_unit_id",
        "manager_id",
        "business_line",
        array_item(
            ["Phoenix", "Tampa", "New York", "Chicago", "Dallas", "San Francisco"],
            F.pmod(F.col("org_index"), F.lit(6)).cast("int"),
        ).alias("location"),
        F.when(stable_fraction(seed, 11, F.col("worker_index")) < 0.92, "Full Time")
        .otherwise("Part Time")
        .alias("worker_type"),
    ).withColumn("email", F.concat(F.col("email_local_part"), F.lit("@fictionalbank.example"))).drop(
        "email_local_part"
    )
    return workers_core, workers


def build_job_history(workers_core: DataFrame, seed: int) -> DataFrame:
    role_index = F.col("role_index")
    line_index = F.col("line_index")
    prior_job_code = F.concat(
        array_item(JOB_PREFIXES, line_index),
        F.format_string("%02d", F.greatest(role_index, F.lit(1))),
    )
    prior_org_index = F.pmod(F.col("org_index") + F.lit(1), F.lit(ORG_UNIT_COUNT))
    prior_org_unit_id = F.format_string("ORG%03d", prior_org_index + F.lit(1))
    prior_manager_id = F.format_string(
        "EMP%06d", F.pmod(F.col("worker_index") + F.lit(72), F.lit(288)) + F.lit(1)
    )
    hire_events = workers_core.select(
        F.concat(F.col("worker_id"), F.lit("-HIRE")).alias("event_id"),
        "worker_id",
        F.lit("HIRE").alias("event_type"),
        F.col("hire_date").alias("event_date"),
        F.when(F.col("promotion_flag"), prior_job_code).otherwise(F.col("job_code")).alias(
            "job_code"
        ),
        F.lit(None).cast("string").alias("previous_job_code"),
        F.when(F.col("transfer_flag"), prior_org_unit_id)
        .otherwise(F.col("org_unit_id"))
        .alias("org_unit_id"),
        F.lit(None).cast("string").alias("previous_org_unit_id"),
        F.when(F.col("manager_change_flag"), prior_manager_id)
        .otherwise(F.col("manager_id"))
        .alias("manager_id"),
        F.lit(None).cast("string").alias("previous_manager_id"),
        F.lit(None).cast("string").alias("termination_type"),
        F.lit("Initial hire").alias("event_reason"),
    )
    promotion_date = F.date_add(
        F.lit(HISTORY_START),
        (stable_mod(seed, 510, 12, F.col("worker_index")) + F.lit(30)).cast("int"),
    )
    promotion_events = workers_core.where(
        F.col("promotion_flag")
        & (F.col("termination_date").isNull() | (promotion_date < F.col("termination_date")))
    ).select(
        F.concat(F.col("worker_id"), F.lit("-PROMOTION")).alias("event_id"),
        "worker_id",
        F.lit("PROMOTION").alias("event_type"),
        promotion_date.alias("event_date"),
        "job_code",
        prior_job_code.alias("previous_job_code"),
        "org_unit_id",
        F.col("org_unit_id").alias("previous_org_unit_id"),
        "manager_id",
        F.col("manager_id").alias("previous_manager_id"),
        F.lit(None).cast("string").alias("termination_type"),
        F.lit("Merit promotion").alias("event_reason"),
    )
    transfer_date = F.date_add(
        F.lit(HISTORY_START),
        (stable_mod(seed, 480, 13, F.col("worker_index")) + F.lit(60)).cast("int"),
    )
    transfer_events = workers_core.where(
        F.col("transfer_flag")
        & (F.col("termination_date").isNull() | (transfer_date < F.col("termination_date")))
    ).select(
        F.concat(F.col("worker_id"), F.lit("-TRANSFER")).alias("event_id"),
        "worker_id",
        F.lit("TRANSFER").alias("event_type"),
        transfer_date.alias("event_date"),
        "job_code",
        F.col("job_code").alias("previous_job_code"),
        "org_unit_id",
        prior_org_unit_id.alias("previous_org_unit_id"),
        "manager_id",
        prior_manager_id.alias("previous_manager_id"),
        F.lit(None).cast("string").alias("termination_type"),
        F.lit("Internal mobility").alias("event_reason"),
    )
    manager_change_date = F.date_add(
        F.lit(HISTORY_START),
        (stable_mod(seed, 450, 14, F.col("worker_index")) + F.lit(90)).cast("int"),
    )
    manager_change_events = workers_core.where(
        F.col("manager_change_flag")
        & (
            F.col("termination_date").isNull()
            | (manager_change_date < F.col("termination_date"))
        )
    ).select(
        F.concat(F.col("worker_id"), F.lit("-MANAGER")).alias("event_id"),
        "worker_id",
        F.lit("MANAGER_CHANGE").alias("event_type"),
        manager_change_date.alias("event_date"),
        "job_code",
        F.col("job_code").alias("previous_job_code"),
        "org_unit_id",
        F.col("org_unit_id").alias("previous_org_unit_id"),
        "manager_id",
        prior_manager_id.alias("previous_manager_id"),
        F.lit(None).cast("string").alias("termination_type"),
        F.lit("Organization change").alias("event_reason"),
    )
    exit_events = workers_core.where(F.col("termination_date").isNotNull()).select(
        F.concat(F.col("worker_id"), F.lit("-EXIT")).alias("event_id"),
        "worker_id",
        F.lit("EXIT").alias("event_type"),
        F.col("termination_date").alias("event_date"),
        "job_code",
        F.col("job_code").alias("previous_job_code"),
        "org_unit_id",
        F.col("org_unit_id").alias("previous_org_unit_id"),
        "manager_id",
        F.col("manager_id").alias("previous_manager_id"),
        F.when(
            F.col("contact_center_flag") & F.col("target_manager_flag"), "Voluntary"
        )
        .when(stable_fraction(seed, 15, F.col("worker_index")) < 0.72, "Voluntary")
        .otherwise("Involuntary")
        .alias("termination_type"),
        F.when(
            F.col("contact_center_flag") & F.col("target_manager_flag"),
            "Schedule and workload following operating model change",
        )
        .otherwise("Standard employee departure")
        .alias("event_reason"),
    )
    return (
        hire_events.unionByName(promotion_events)
        .unionByName(transfer_events)
        .unionByName(manager_change_events)
        .unionByName(exit_events)
    )


def build_engagement_surveys(
    spark: SparkSession, workers_core: DataFrame, seed: int
) -> DataFrame:
    wave_index = F.col("wave_index")
    waves = spark.range(8, numPartitions=1).withColumnRenamed("id", "wave_index").select(
        wave_index,
        F.add_months(F.lit("2024-12-15").cast("date"), (wave_index * F.lit(3)).cast("int")).alias(
            "survey_date"
        ),
    )
    survey_base = workers_core.select(
        "worker_index",
        "worker_id",
        "org_unit_id",
        "manager_id",
        "termination_date",
        "fraud_operations_flag",
        "contact_center_flag",
        "standout_team_flag",
    ).crossJoin(waves)
    survey_base = survey_base.where(
        F.col("termination_date").isNull() | (F.col("survey_date") <= F.col("termination_date"))
    )
    noise = (
        stable_fraction(seed, 16, F.col("worker_index"), F.col("wave_index")) - F.lit(0.5)
    ) * F.lit(0.6)
    fraud_score = F.lit(4.15) - F.greatest(
        F.col("wave_index") - F.lit(2), F.lit(0)
    ) * F.lit(0.34)
    contact_center_score = F.lit(3.75) - F.when(F.col("wave_index") >= 5, 0.95).otherwise(0.0)
    score = F.round(
        F.least(
            F.lit(5.0),
            F.greatest(
                F.lit(1.0),
                F.when(F.col("standout_team_flag"), F.lit(4.65))
                .when(F.col("fraud_operations_flag"), fraud_score)
                .when(F.col("contact_center_flag"), contact_center_score)
                .otherwise(F.lit(3.85))
                + noise,
            ),
        ),
        1,
    )
    comment = (
        F.when(
            F.col("fraud_operations_flag") & (F.col("wave_index") >= 4),
            "Sustained overtime and rising workload are causing burnout; staffing has not kept pace with fraud alerts.",
        )
        .when(
            F.col("contact_center_flag") & (F.col("wave_index") >= 5),
            "The new schedule is difficult to manage and the workload leaves too little recovery time between shifts.",
        )
        .when(
            F.col("standout_team_flag"),
            "My manager recognizes strong work, removes obstacles, and keeps the team focused on customers.",
        )
        .when(score >= 4.0, "I feel supported and understand how my work contributes to the bank.")
        .otherwise("Work is manageable, though clearer priorities and more recognition would help.")
    )
    return survey_base.select(
        F.concat(
            F.lit("SURV-"),
            F.format_string("%06d", F.col("worker_index") + F.lit(1)),
            F.lit("-"),
            F.format_string("%02d", F.col("wave_index") + F.lit(1)),
        ).alias("survey_response_id"),
        "worker_id",
        "org_unit_id",
        "manager_id",
        F.concat(F.lit("2024Q4-W"), F.col("wave_index") + F.lit(1)).alias("survey_wave"),
        "survey_date",
        score.alias("engagement_score"),
        F.round(F.least(F.lit(5.0), score + F.lit(0.1)), 1).alias("manager_score"),
        F.round(F.greatest(F.lit(1.0), score - F.lit(0.2)), 1).alias("workload_score"),
        comment.alias("comment"),
    )


def build_exit_interviews(workers_core: DataFrame, seed: int) -> DataFrame:
    ordinary_reason_index = stable_mod(seed, 5, 17, F.col("worker_index")).cast("int")
    stated_reason = (
        F.when(
            F.col("contact_center_flag") & F.col("target_manager_flag"),
            "schedule and workload",
        )
        .otherwise(
            array_item(
                ["compensation", "manager", "career growth", "relocation", "other"],
                ordinary_reason_index,
            )
        )
    )
    comment = (
        F.when(
            F.col("contact_center_flag") & F.col("target_manager_flag"),
            "The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role.",
        )
        .when(stated_reason == "compensation", "My compensation fell behind comparable banking roles, so I accepted a better offer.")
        .when(stated_reason == "manager", "I wanted clearer priorities, more consistent coaching, and stronger support from my manager.")
        .when(stated_reason == "career growth", "I could not see a timely path to promotion or broader responsibilities.")
        .when(stated_reason == "relocation", "I am relocating outside the bank's current operating footprint.")
        .otherwise("I am leaving for a combination of personal priorities and a different opportunity.")
    )
    return workers_core.where(F.col("termination_date").isNotNull()).select(
        F.concat(F.lit("EXIT-"), F.col("worker_id")).alias("exit_interview_id"),
        "worker_id",
        "org_unit_id",
        "manager_id",
        F.col("termination_date").alias("exit_date"),
        F.date_add(F.col("termination_date"), 5).alias("interview_date"),
        stated_reason.alias("stated_reason"),
        comment.alias("exit_comment"),
        (stable_fraction(seed, 18, F.col("worker_index")) < 0.68).alias("would_rehire"),
    )


def build_team_productivity(spark: SparkSession, seed: int) -> DataFrame:
    org_index = F.col("org_index")
    month_index = F.col("month_index")
    orgs = spark.range(ORG_UNIT_COUNT, numPartitions=1).withColumnRenamed("id", "org_index")
    months = spark.range(24, numPartitions=1).withColumnRenamed("id", "month_index")
    base = orgs.crossJoin(months)
    fraud_operations = org_index.isin(36, 37)
    contact_center = org_index.isin(0, 1)
    standout_team = org_index.isin(10, 11, 38)
    late_period = month_index >= 12
    schedule_period = month_index >= 16
    noise = stable_fraction(seed, 19, org_index, month_index) - F.lit(0.5)
    overtime = F.round(
        F.when(fraud_operations & late_period, F.lit(260.0) + noise * 50)
        .when(contact_center & schedule_period, F.lit(210.0) + noise * 40)
        .when(standout_team, F.lit(70.0) + noise * 20)
        .otherwise(F.lit(105.0) + noise * 45),
        1,
    )
    csat = F.round(
        F.when(fraud_operations & late_period, F.lit(3.55) + noise * 0.35)
        .when(contact_center & schedule_period, F.lit(3.65) + noise * 0.3)
        .when(standout_team, F.lit(4.75) + noise * 0.2)
        .otherwise(F.lit(4.25) + noise * 0.35),
        2,
    )
    return base.select(
        F.format_string("ORG%03d", org_index + F.lit(1)).alias("team_id"),
        F.add_months(F.lit(HISTORY_START), month_index.cast("int")).alias("month"),
        (
            F.lit(8_500)
            + stable_mod(seed, 2_000, 20, org_index, month_index)
            + F.when(standout_team, 1_100).otherwise(0)
        ).alias("cases_handled"),
        F.round(
            F.when(fraud_operations & late_period, F.lit(18.0) + noise * 2.0)
            .when(contact_center & schedule_period, F.lit(14.5) + noise * 1.5)
            .when(standout_team, F.lit(8.4) + noise)
            .otherwise(F.lit(10.5) + noise * 1.5),
            2,
        ).alias("avg_handle_time_minutes"),
        csat.alias("csat_score"),
        overtime.alias("overtime_hours"),
        F.round(
            F.when(standout_team, F.lit(97.0) + noise * 2.0)
            .when(fraud_operations & late_period, F.lit(87.0) + noise * 3.0)
            .otherwise(F.lit(93.0) + noise * 3.0),
            1,
        ).alias("quality_score"),
    )


def build_performance_reviews(
    spark: SparkSession, workers_core: DataFrame, seed: int
) -> DataFrame:
    review_years = spark.createDataFrame([(2025,), (2026,)], ["review_year"])
    base = workers_core.select(
        "worker_index",
        "worker_id",
        "job_code",
        "org_unit_id",
        "manager_id",
        "stalled_high_performer_flag",
        "standout_team_flag",
    ).crossJoin(review_years)
    rating_fraction = stable_fraction(
        seed, 21, F.col("worker_index"), F.col("review_year")
    )
    rating = (
        F.when(F.col("stalled_high_performer_flag"), "Exceeds Expectations")
        .when(F.col("standout_team_flag") & (rating_fraction < 0.65), "Exceeds Expectations")
        .when(rating_fraction < 0.08, "Exceeds Expectations")
        .when(rating_fraction < 0.78, "Meets Expectations")
        .when(rating_fraction < 0.95, "Partially Meets")
        .otherwise("Does Not Meet")
    )
    rating_numeric = (
        F.when(rating == "Exceeds Expectations", 5)
        .when(rating == "Meets Expectations", 4)
        .when(rating == "Partially Meets", 3)
        .otherwise(2)
    )
    comment = (
        F.when(
            F.col("stalled_high_performer_flag"),
            "Delivered exceptional AI and data outcomes, mentors peers, and demonstrates advanced SQL, machine learning, and stakeholder leadership skills. Ready for broader scope.",
        )
        .when(
            F.col("standout_team_flag"),
            "Consistently exceeds customer and quality goals while strengthening collaboration across the team.",
        )
        .when(rating_numeric >= 4, "Reliable performance with strong customer focus, controls, and collaboration.")
        .otherwise("Performance is improving; focus on execution consistency, prioritization, and quality controls.")
    )
    return base.select(
        F.concat(
            F.lit("REV-"), F.col("worker_id"), F.lit("-"), F.col("review_year")
        ).alias("review_id"),
        "worker_id",
        "review_year",
        F.make_date(F.col("review_year"), F.lit(12), F.lit(15)).alias("review_date"),
        "job_code",
        "org_unit_id",
        "manager_id",
        rating.alias("performance_rating"),
        rating_numeric.alias("rating_numeric"),
        F.when(F.col("stalled_high_performer_flag"), "High")
        .when(rating_numeric == 5, "High")
        .when(rating_numeric >= 4, "Medium")
        .otherwise("Developing")
        .alias("potential_rating"),
        comment.alias("manager_comment"),
    )


def build_compensation(spark: SparkSession, workers_core: DataFrame, seed: int) -> DataFrame:
    compensation_years = spark.createDataFrame([(2025,), (2026,)], ["compensation_year"])
    base = workers_core.select(
        "worker_index",
        "worker_id",
        "job_code",
        "org_unit_id",
        "role_index",
        "line_index",
        "stalled_high_performer_flag",
    ).crossJoin(compensation_years)
    band_midpoint = (
        F.lit(52_000.0)
        + F.col("role_index") * F.lit(8_500.0)
        + F.when(F.col("line_index") == 4, 24_000.0)
        .when(F.col("line_index") == 1, 14_000.0)
        .otherwise(0.0)
    )
    pay_position = (
        F.when(
            F.col("stalled_high_performer_flag") & (F.col("compensation_year") == 2026),
            F.lit(0.86)
            + stable_fraction(seed, 22, F.col("worker_index")) * F.lit(0.07),
        )
        .otherwise(
            F.lit(0.93)
            + stable_fraction(
                seed, 23, F.col("worker_index"), F.col("compensation_year")
            )
            * F.lit(0.24)
        )
    )
    base_salary = F.round(band_midpoint * pay_position, 2)
    return base.select(
        F.concat(
            F.lit("COMP-"),
            F.col("worker_id"),
            F.lit("-"),
            F.col("compensation_year"),
        ).alias("compensation_id"),
        "worker_id",
        "compensation_year",
        F.make_date(F.col("compensation_year"), F.lit(12), F.lit(31)).alias(
            "effective_date"
        ),
        "job_code",
        "org_unit_id",
        base_salary.alias("base_salary"),
        F.round(
            base_salary
            * (
                F.lit(0.05)
                + stable_fraction(
                    seed, 24, F.col("worker_index"), F.col("compensation_year")
                )
                * F.lit(0.15)
            ),
            2,
        ).alias("annual_bonus"),
        F.round(band_midpoint * F.lit(0.80), 2).alias("band_min"),
        F.round(band_midpoint, 2).alias("band_mid"),
        F.round(band_midpoint * F.lit(1.25), 2).alias("band_max"),
        F.lit("USD").alias("currency"),
    )


def build_requisitions(spark: SparkSession, seed: int) -> DataFrame:
    requisition_index = F.col("requisition_index")
    month_index = F.floor(requisition_index / F.lit(100)).cast("int")
    month_position = F.pmod(requisition_index, F.lit(100)).cast("int")
    contact_center_backfill = month_index.between(17, 20) & (month_position < 40)
    ordinary_org_index = stable_mod(seed, ORG_UNIT_COUNT, 25, requisition_index).cast("int")
    org_index = F.when(
        contact_center_backfill, F.pmod(month_position, F.lit(2)).cast("int")
    ).otherwise(ordinary_org_index)
    line_index = F.floor(org_index / F.lit(12)).cast("int")
    ordinary_role_index = stable_mod(seed, 10, 26, requisition_index).cast("int")
    role_index = F.when(
        contact_center_backfill, F.pmod(month_position, F.lit(2)).cast("int")
    ).otherwise(ordinary_role_index)
    job_code = F.concat(
        array_item(JOB_PREFIXES, line_index), F.format_string("%02d", role_index + F.lit(1))
    )
    licensed_role = ((line_index == 1) & (role_index <= 2)) | (
        (line_index == 0) & (role_index == 8)
    )
    open_date = F.date_add(
        F.add_months(F.lit(HISTORY_START), month_index),
        stable_mod(seed, 24, 27, requisition_index).cast("int"),
    )
    time_to_fill = (
        F.when(licensed_role, F.lit(78) + stable_mod(seed, 38, 28, requisition_index))
        .when(contact_center_backfill, F.lit(42) + stable_mod(seed, 22, 29, requisition_index))
        .otherwise(F.lit(32) + stable_mod(seed, 28, 30, requisition_index))
        .cast("int")
    )
    planned_close_date = F.date_add(open_date, time_to_fill)
    cancelled = stable_fraction(seed, 31, requisition_index) < 0.06
    status = (
        F.when(cancelled, "Cancelled")
        .when(planned_close_date <= F.lit(AS_OF_DATE), "Filled")
        .otherwise("Open")
    )
    return (
        spark.range(REQUISITION_COUNT, numPartitions=8)
        .withColumnRenamed("id", "requisition_index")
        .select(
            requisition_index,
            F.format_string("REQ%06d", requisition_index + F.lit(1)).alias("requisition_id"),
            job_code.alias("job_code"),
            F.format_string("ORG%03d", org_index + F.lit(1)).alias("org_unit_id"),
            array_item(BUSINESS_LINES, line_index).alias("business_line"),
            open_date.alias("open_date"),
            F.when(status == "Open", F.lit(None).cast("date"))
            .when(status == "Cancelled", F.date_add(open_date, 20))
            .otherwise(planned_close_date)
            .alias("close_date"),
            status.alias("status"),
            F.when(contact_center_backfill, "Backfill")
            .when(stable_fraction(seed, 32, requisition_index) < 0.58, "Backfill")
            .otherwise("New")
            .alias("requisition_type"),
            licensed_role.alias("licensed_role_flag"),
            F.round(
                F.when(licensed_role, F.lit(18_000.0))
                .when(contact_center_backfill, F.lit(9_500.0))
                .otherwise(F.lit(7_500.0))
                + stable_mod(seed, 4_000, 33, requisition_index),
                2,
            ).alias("estimated_recruiting_cost"),
        )
    )


def build_applications(requisitions: DataFrame, spark: SparkSession, seed: int) -> DataFrame:
    application_index = F.col("application_index")
    requisition_index = F.floor(
        application_index / F.lit(APPLICATIONS_PER_REQUISITION)
    ).cast("long")
    application_slot = F.pmod(
        application_index, F.lit(APPLICATIONS_PER_REQUISITION)
    ).cast("int")
    application_base = (
        spark.range(
            REQUISITION_COUNT * APPLICATIONS_PER_REQUISITION, numPartitions=16
        )
        .withColumnRenamed("id", "application_index")
        .withColumn("requisition_index", requisition_index)
        .withColumn("application_slot", application_slot)
        .join(
            requisitions.select(
                "requisition_index",
                "requisition_id",
                "job_code",
                "org_unit_id",
                "open_date",
                "status",
                "licensed_role_flag",
            ),
            "requisition_index",
        )
    )
    technology_target = F.col("job_code").startswith("TEC")
    genai_mobility_candidate = technology_target & F.col("application_slot").isin(2, 3)
    ordinary_internal_candidate = F.col("application_slot") == 4
    internal_candidate = genai_mobility_candidate | ordinary_internal_candidate
    source_org_index = F.when(
        genai_mobility_candidate,
        F.lit(36) + F.pmod(F.col("application_index"), F.lit(2)),
    ).otherwise(stable_mod(seed, ORG_UNIT_COUNT, 34, F.col("application_index")))
    source_role_index = F.when(
        genai_mobility_candidate,
        F.pmod(F.col("application_index"), F.lit(3)),
    ).otherwise(stable_mod(seed, 10, 35, F.col("application_index")))
    worker_cycle = stable_mod(seed, 27, 36, F.col("application_index"))
    internal_worker_index = source_org_index + F.lit(72) * (
        worker_cycle * F.lit(10) + source_role_index
    )
    final_stage = (
        F.when((F.col("application_slot") == 0) & (F.col("status") == "Filled"), "Hired")
        .when((F.col("application_slot") == 1) & (F.col("status") == "Filled"), "Declined")
        .when(F.col("application_slot") == 2, "Offer")
        .when(F.col("application_slot").isin(3, 4), "Interview")
        .when(F.col("application_slot").isin(5, 6), "Screen")
        .otherwise("Rejected")
    )
    candidate_summary = (
        F.when(
            genai_mobility_candidate,
            "Internal operations candidate with adjacent skills in SQL, data quality, process automation, controls, customer judgment, and fraud case analysis; completed bank-sponsored data training.",
        )
        .when(
            F.col("licensed_role_flag"),
            "Experienced client-facing banking candidate with relationship management, regulated product knowledge, and relevant licensing preparation.",
        )
        .when(
            internal_candidate,
            "Internal candidate with strong institutional knowledge, customer focus, controls experience, and transferable banking skills.",
        )
        .otherwise(
            "External candidate with relevant industry experience, collaborative delivery skills, and a record of measurable customer outcomes."
        )
    )
    decline_comment = (
        F.when(
            (final_stage == "Declined")
            & F.col("licensed_role_flag")
            & (F.pmod(F.col("application_index"), F.lit(2)) == 0),
            "Base compensation and the transition package were below another advisory firm's offer.",
        )
        .when(
            (final_stage == "Declined") & F.col("licensed_role_flag"),
            "Accepted a competing offer with a stronger client book and faster compensation ramp.",
        )
        .when(final_stage == "Declined", "Accepted another role that was a closer fit for current goals.")
    )
    return application_base.select(
        "application_index",
        F.format_string("APP%07d", F.col("application_index") + F.lit(1)).alias(
            "application_id"
        ),
        F.format_string("CAND%07d", F.col("application_index") + F.lit(1)).alias(
            "candidate_id"
        ),
        "requisition_id",
        F.date_add(
            F.col("open_date"),
            stable_mod(seed, 15, 37, F.col("application_index")).cast("int"),
        ).alias("application_date"),
        F.when(internal_candidate, "Internal")
        .otherwise(
            array_item(
                ["Careers Site", "Employee Referral", "LinkedIn", "Agency"],
                stable_mod(seed, 4, 38, F.col("application_index")).cast("int"),
            )
        )
        .alias("source"),
        F.when(
            internal_candidate,
            F.format_string("EMP%06d", internal_worker_index + F.lit(1)),
        ).alias("internal_worker_id"),
        final_stage.alias("current_stage"),
        F.when(final_stage == "Hired", "Accepted")
        .when(final_stage == "Declined", "Declined")
        .when(final_stage == "Offer", "Pending")
        .otherwise("Not Offered")
        .alias("offer_outcome"),
        candidate_summary.alias("candidate_summary"),
        decline_comment.alias("offer_decline_comment"),
    )


def build_application_events(applications: DataFrame, seed: int) -> DataFrame:
    max_stage = (
        F.when(F.col("current_stage").isin("Hired", "Declined"), 4)
        .when(F.col("current_stage") == "Offer", 3)
        .when(F.col("current_stage") == "Interview", 2)
        .when(F.col("current_stage") == "Screen", 1)
        .otherwise(
            F.lit(1) + stable_mod(seed, 2, 39, F.col("application_index")).cast("int")
        )
    )
    expanded = applications.withColumn(
        "event_index", F.explode(F.sequence(F.lit(0), max_stage))
    )
    normal_stage = array_item(
        ["Applied", "Screen", "Interview", "Offer", "Hired"], F.col("event_index")
    )
    event_stage = F.when(
        (F.col("event_index") == max_stage)
        & F.col("current_stage").isin("Hired", "Declined", "Rejected"),
        F.col("current_stage"),
    ).otherwise(normal_stage)
    return expanded.select(
        F.concat(
            F.col("application_id"),
            F.lit("-E"),
            F.format_string("%02d", F.col("event_index") + F.lit(1)),
        ).alias("application_event_id"),
        "application_id",
        "requisition_id",
        event_stage.alias("stage"),
        F.date_add(
            F.col("application_date"),
            (
                F.col("event_index") * F.lit(5)
                + stable_mod(
                    seed,
                    4,
                    40,
                    F.col("application_index"),
                    F.col("event_index"),
                )
            ).cast("int"),
        ).alias("event_date"),
        F.when(event_stage.isin("Rejected", "Declined"), "Closed")
        .when(event_stage == "Hired", "Completed")
        .otherwise("Advanced")
        .alias("stage_status"),
    )


def write_csv(dataframe: DataFrame, landing_path: str, dataset: str, partitions: int) -> None:
    (
        dataframe.repartition(partitions)
        .write.mode("overwrite")
        .option("header", "true")
        .option("dateFormat", "yyyy-MM-dd")
        .csv(f"{landing_path}/{dataset}")
    )
    print(f"Wrote CSV dataset: {dataset}")


def write_json(dataframe: DataFrame, landing_path: str, dataset: str, partitions: int) -> None:
    dataframe.repartition(partitions).write.mode("overwrite").json(
        f"{landing_path}/{dataset}"
    )
    print(f"Wrote JSON dataset: {dataset}")


def main() -> None:
    args = parse_args()
    catalog = validate_identifier(args.catalog)
    bronze_schema = validate_identifier(args.bronze_schema)
    volume_name = volume_name_from_path(args.landing_path, catalog, bronze_schema)
    spark = create_session(args.profile)
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.`{bronze_schema}`")
    spark.sql(
        f"CREATE VOLUME IF NOT EXISTS `{catalog}`.`{bronze_schema}`.`{volume_name}`"
    )

    jobs = build_jobs(spark)
    org_units = build_org_units(spark)
    workers_core, workers = build_workers(spark, args.worker_count, args.seed)
    job_history = build_job_history(workers_core, args.seed)
    engagement_surveys = build_engagement_surveys(spark, workers_core, args.seed)
    exit_interviews = build_exit_interviews(workers_core, args.seed)
    team_productivity = build_team_productivity(spark, args.seed)
    performance_reviews = build_performance_reviews(spark, workers_core, args.seed)
    compensation = build_compensation(spark, workers_core, args.seed)
    requisitions = build_requisitions(spark, args.seed)
    applications = build_applications(requisitions, spark, args.seed)
    application_events = build_application_events(applications, args.seed)

    write_csv(workers, args.landing_path, "workers", 8)
    write_csv(job_history, args.landing_path, "job_history", 8)
    write_csv(org_units, args.landing_path, "org_units", 1)
    write_json(jobs, args.landing_path, "jobs", 1)
    write_json(engagement_surveys, args.landing_path, "engagement_surveys", 16)
    write_json(exit_interviews, args.landing_path, "exit_interviews", 4)
    write_csv(team_productivity, args.landing_path, "team_productivity", 4)
    write_json(performance_reviews, args.landing_path, "performance_reviews", 8)
    write_csv(compensation, args.landing_path, "compensation", 8)
    write_csv(requisitions.drop("requisition_index"), args.landing_path, "requisitions", 4)
    write_json(applications.drop("application_index"), args.landing_path, "applications", 8)
    write_csv(application_events, args.landing_path, "application_events", 16)
    print(f"Generation complete: seed={args.seed}, workers={args.worker_count}")


if __name__ == "__main__":
    main()
