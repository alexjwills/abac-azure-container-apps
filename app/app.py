"""Tests tag-based access to Azure Blob Storage.

Lists every container and blob, then tries to read four test blobs.
Access is decided by the identity the code runs as, not by anything in this script.
"""
import os
import sys

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

# The storage account name comes from the environment, not the code.
ACCOUNT_NAME = os.environ.get("AZURE_STORAGE_ACCOUNT")
if not ACCOUNT_NAME:
    sys.exit("AZURE_STORAGE_ACCOUNT is not set")

ACCOUNT_URL = f"https://{ACCOUNT_NAME}.blob.core.windows.net"

# Each test is (container, blob).
TESTS = [
    ("engineering", "engineering-report.txt"),
    ("finance", "finance-report.txt"),
    ("marketing", "marketing-report.txt"),
    ("engineering", "untagged.txt"),
]

credential = DefaultAzureCredential()
service = BlobServiceClient(account_url=ACCOUNT_URL, credential=credential)

print(f"Listing blobs in {ACCOUNT_NAME}")
for container in service.list_containers():
    container_client = service.get_container_client(container.name)
    for blob in container_client.list_blobs():
        print(f"  {container.name}/{blob.name}")

print("Reading test blobs")
for container_name, blob_name in TESTS:
    blob_client = service.get_blob_client(container=container_name, blob=blob_name)
    try:
        content = blob_client.download_blob().readall().decode().strip()
        print(f"  GRANTED  {container_name}/{blob_name}: {content}")
    except HttpResponseError as err:
        print(f"  DENIED   {container_name}/{blob_name}: {err.status_code} {err.error_code}")