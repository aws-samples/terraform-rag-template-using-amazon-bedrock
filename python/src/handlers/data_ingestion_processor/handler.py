# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import os
from functools import lru_cache
from typing import Any, Dict, List

import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext
from langchain.schema.document import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import S3FileLoader
from langchain_community.embeddings.bedrock import BedrockEmbeddings
from langchain_community.vectorstores.pgvector import (DistanceStrategy,
                                                       PGVector)
from langchain_core.embeddings import Embeddings
from langchain_core.vectorstores import VectorStore

tracer = Tracer()
logger = Logger()

boto_session = boto3.Session()

DDB_TABLE_NAME = os.getenv("DDB_TABLE_NAME")
VECTOR_DB_INDEX = os.getenv("VECTOR_DB_INDEX")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP"))

EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID")

PG_VECTOR_DB_NAME = os.getenv("PG_VECTOR_DB_NAME")
PG_VECTOR_SECRET_ARN = os.getenv("PG_VECTOR_SECRET_ARN")
PG_VECTOR_DB_HOST = os.getenv("PG_VECTOR_DB_HOST")
PG_VECTOR_PORT = os.getenv("PG_VECTOR_PORT", "5432")


@logger.inject_lambda_context
@tracer.capture_method(capture_response=False)
def lambda_handler(event: Dict[str, Any], _: LambdaContext):
    """Lambda handler example"""
    try:
        logger.info(f"DDB_TABLE_NAME: {DDB_TABLE_NAME}")
        logger.info(f"Event: {event}")

        if len(event.get("Records", [])) == 0:
            return {
                "statusCode": 400,
                "body": "No records received.",
            }

        # Create a single DB connection for entire Lambda runtime
        vector_store = get_vector_store()

        logger.info("Going to chunk the records")
        for record in event.get("Records", []):
            bucket = record["s3"]["bucket"]["name"]
            key = record["s3"]["object"]["key"]

            s3Loader = S3FileLoader(bucket=bucket, key=key)
            documents = s3Loader.load()
            chunks = chunk_documents(documents)
            vector_store.add_documents(chunks)

        return {
            "statusCode": 200,
            "body": f"Success. Received {len(chunks)} chunks",
        }
    except Exception as e:
        logger.exception("Unable to ingest documents.")
        raise e


def chunk_documents(documents=List[Document]) -> List[Document]:
    """
    Split a list of documents into smaller chunks based on the specified chunk size and overlap.

    Args:
        documents (List[Document]): A list of Document objects to be split.

    Returns:
        List[Document]: A list of Document objects after splitting into smaller chunks.
    """
    logger.info(
        f"Chunking {len(documents)} documents with chunk size {CHUNK_SIZE} and overlap {CHUNK_OVERLAP}",
    )
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )
    return text_splitter.split_documents(documents)


def get_vector_store() -> VectorStore:
    """Get vector data base connection"""
    logger.info(f"Retrieving secret with arn '{PG_VECTOR_SECRET_ARN}'")
    credentials = _get_db_secret_value()
    connection = PGVector.connection_string_from_db_params(
        driver="psycopg2",
        host=PG_VECTOR_DB_HOST,
        port=PG_VECTOR_PORT,
        database=PG_VECTOR_DB_NAME,
        user=credentials.get("username"),
        password=credentials.get("password"),
    )

    return PGVector(
        connection_string=connection,
        collection_name=VECTOR_DB_INDEX,
        embedding_function=get_embedding_model(),
        distance_strategy=DistanceStrategy.COSINE,
    )


@lru_cache  # model can be cached
def get_embedding_model(
    model_id=EMBEDDING_MODEL_ID,
) -> Embeddings:
    """Get embedding model"""
    logger.info(f"Using embedding model: {model_id}")
    client = boto_session.client("bedrock-runtime")
    return BedrockEmbeddings(client=client, model_id=model_id)


@lru_cache  # loaded secret can be cached
def _get_db_secret_value() -> Dict[str, str]:
    """Retrieve the secret value from the Secrets Manger for the RDS data base

    Raises:
        e: ClientError if client is not set up properly

    Returns:
        Dict[str, str]: Dictionary that holds 'password' and 'username'
    """
    client = boto_session.client(service_name="secretsmanager")
    get_secret_value_response = client.get_secret_value(
        SecretId=PG_VECTOR_SECRET_ARN,
    )
    return json.loads(get_secret_value_response["SecretString"])
