import os
from unittest.mock import MagicMock, patch

import pytest
from aws_lambda_powertools.utilities.data_classes import S3Event
from aws_lambda_powertools.utilities.typing import LambdaContext

os.environ["CHUNK_SIZE"] = "1000"
os.environ["CHUNK_OVERLAP"] = "100"

from python.src.handlers.data_ingestion_processor.handler import (  # noqa: E402
    lambda_handler,
)


def test_lambda_handler_exception_handling():
    """
    Test lambda_handler's exception handling.
    This tests the scenario where an exception is raised during processing.
    """
    mock_event = S3Event(
        {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "test-key"},
                    },
                },
            ],
        },
    )
    context = LambdaContext()

    # Simulate an exception during processing
    with pytest.raises(Exception):
        lambda_handler(mock_event, context)


def test_lambda_handler_success():
    """
    Test that lambda_handler successfully processes S3 events and returns a 200 status code.

    This test verifies that:
    1. The function correctly handles S3 events
    2. It processes all records in the event
    3. It returns the expected success response
    """
    # Mock S3Event
    mock_event = S3Event(
        {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "test-key"},
                    },
                },
            ],
        },
    )

    # Mock LambdaContext
    mock_context = MagicMock(spec=LambdaContext)

    # Mock dependencies
    with patch(
        "python.src.handlers.data_ingestion_processor.handler.get_vector_store",
    ) as mock_get_vector_store, patch(
        "python.src.handlers.data_ingestion_processor.handler.S3FileLoader",
    ) as mock_s3_loader, patch(
        "python.src.handlers.data_ingestion_processor.handler.asyncio.run",
    ) as mock_asyncio_run:
        # Set up mock returns
        mock_vector_store = MagicMock()
        mock_get_vector_store.return_value = mock_vector_store

        mock_s3_loader_instance = MagicMock()
        mock_s3_loader.return_value = mock_s3_loader_instance
        mock_s3_loader_instance.load_and_split.return_value = [MagicMock(), MagicMock()]

        # Call the function
        result = lambda_handler(mock_event, mock_context)

        # Assertions
        assert result == {
            "statusCode": 200,
            "body": "Success.",
        }

        mock_get_vector_store.assert_called_once()
        mock_s3_loader.assert_called_once_with(bucket="test-bucket", key="test-key")
        mock_s3_loader_instance.load_and_split.assert_called_once()
        mock_vector_store.aadd_documents.assert_called_once_with(
            mock_s3_loader_instance.load_and_split.return_value,
        )
        mock_asyncio_run.assert_called_once()
