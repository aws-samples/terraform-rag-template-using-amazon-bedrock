# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import asyncio
import os
from functools import cache
from urllib.parse import unquote_plus

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.data_classes import S3Event, event_source
from aws_lambda_powertools.utilities.parameters import get_secret
from aws_lambda_powertools.utilities.typing import LambdaContext
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_aws.embeddings import BedrockEmbeddings
from langchain_community.document_loaders import S3FileLoader
from langchain_core.embeddings import Embeddings
from langchain_core.vectorstores import VectorStore
from langchain_postgres.vectorstores import DistanceStrategy, PGVector

tracer = Tracer()
logger = Logger()

VECTOR_DB_INDEX = os.getenv("VECTOR_DB_INDEX")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP"))

EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID")

PG_VECTOR_DB_NAME = os.getenv("PG_VECTOR_DB_NAME")
PG_VECTOR_SECRET_ARN = os.getenv("PG_VECTOR_SECRET_ARN")
PG_VECTOR_DB_HOST = os.getenv("PG_VECTOR_DB_HOST")
PG_VECTOR_PORT = os.getenv("PG_VECTOR_PORT", "5432")


@logger.inject_lambda_context(log_event=True)
@tracer.capture_method(capture_response=False)
@event_source(data_class=S3Event)
def lambda_handler(event: S3Event, _: LambdaContext):
    """Lambda handler example"""
    try:
        # Create a single DB connection for entire Lambda runtime
        vector_store = get_vector_store()

        for record in event.records:
            bucket = record.s3.bucket.name
            key = unquote_plus(record.s3.get_object.key)
            logger.info(f"Ingesting document. Bucket: {bucket}, Key: {key}")

            s3Loader = S3FileLoader(bucket=bucket, key=key)
            chunks = s3Loader.load_and_split(text_splitter=get_text_splitter())
            # async add will run calls to embedding model in parallel
            asyncio.run(vector_store.aadd_documents(chunks))
            logger.info(f"Successfully ingested {len(chunks)} chunks")

        return {
            "statusCode": 200,
            "body": "Success.",
        }
    except Exception as e:
        logger.exception("Unable to ingest documents.")
        raise e


@cache
def get_text_splitter() -> RecursiveCharacterTextSplitter:
    """Get default text splitter for files based on CHUNK_SIZE and CHUNK_OVERLAP"""
    return RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )


@cache  # vector store connection can be cached
def get_vector_store() -> VectorStore:
    """Get vector data base connection"""
    logger.info(f"Retrieving secret with arn '{PG_VECTOR_SECRET_ARN}'")
    credentials = get_secret(PG_VECTOR_SECRET_ARN, transform="json")
    connection = PGVector.connection_string_from_db_params(
        driver="psycopg",
        host=PG_VECTOR_DB_HOST,
        port=PG_VECTOR_PORT,
        database=PG_VECTOR_DB_NAME,
        user=credentials.get("username"),
        password=credentials.get("password"),
    )

    return PGVector(
        embeddings=get_embedding_model(),
        connection=connection,
        collection_name=VECTOR_DB_INDEX,
        distance_strategy=DistanceStrategy.COSINE,
        async_mode=True,
    )


@cache  # model can be cached
def get_embedding_model(
    model_id=EMBEDDING_MODEL_ID,
) -> Embeddings:
    """Get embedding model"""
    logger.info(f"Using embedding model: {model_id}")
    return BedrockEmbeddings(model_id=model_id)
