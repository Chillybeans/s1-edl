import logging
import azure.functions as func
from azure.storage.blob import BlobServiceClient
import os

# The connection string is automatically pulled from the AzureWebJobsStorage setting
STORAGE_CONNECTION_STRING = os.getenv("AzureWebJobsStorage")
CONTAINER_NAME = '$web'
BLOB_NAME = 'edl.txt'

def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        req_body = req.get_json()
    except ValueError:
        return func.HttpResponse("Invalid request body", status_code=400)

    ip = req_body.get('ip')
    if not ip:
        return func.HttpResponse("Missing IP", status_code=400)

    # Connect to Blob Storage
    blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
    container_client = blob_service_client.get_container_client(CONTAINER_NAME)
    blob_client = container_client.get_blob_client(BLOB_NAME)

    # Download existing IPs
    try:
        existing_data = blob_client.download_blob().readall().decode('utf-8')
        ip_list = set(line.strip() for line in existing_data.splitlines() if line.strip())
    except Exception as e:
        # File might not exist yet
        ip_list = set()

    # Add the new IP if not present
    if ip not in ip_list:
        ip_list.add(ip)
        updated_data = '\n'.join(sorted(ip_list))  # Sorted for neatness

        # Upload the updated list
        blob_client.upload_blob(updated_data, overwrite=True)
        return func.HttpResponse(f"IP {ip} added.", status_code=200)
    else:
        return func.HttpResponse(f"IP {ip} already present.", status_code=200)