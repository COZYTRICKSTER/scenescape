# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import os
import socket
import threading

import numpy as np
from pymilvus import MilvusClient

from controller.reid import ReIDDatabase
from scene_common import log

DEFAULT_HOSTNAME = os.getenv("MILVUS_HOSTNAME", "milvus.scenescape.intel.com")
DEFAULT_PORT = int(os.getenv("MILVUS_PORT", "19530"))
DIMENSIONS = 256
K_NEIGHBORS = 1
COLLECTION_NAME = "reid_vector"
SIMILARITY_METRIC = "L2"

class MilvusDatabase(ReIDDatabase):
  def __init__(self, collection_name=COLLECTION_NAME,
               similarity_metric=SIMILARITY_METRIC, dimensions=DIMENSIONS):
    self.client = None
    self.collection_name = collection_name
    self.similarity_metric = similarity_metric
    self.dimensions = dimensions
    self.lock = threading.Lock()
    self.id_counter = 0
    return

  def connect(self, hostname=DEFAULT_HOSTNAME):
    try:
      # Build connection URI
      uri = f"http://{hostname}:{DEFAULT_PORT}"
      self.client = MilvusClient(uri=uri)
      
      if not self.findSchema(self.collection_name):
        self.addSchema(self.collection_name, self.similarity_metric, self.dimensions)
      log.info(f"Milvus connection ready to {hostname}:{DEFAULT_PORT}")
    except socket.error as e:
      log.warning(f"Failed to connect to Milvus container: {e}")
    except Exception as e:
      log.warning(f"Failed to initialize Milvus client: {e}")
    return

  def addSchema(self, collection_name, similarity_metric, dimensions):
    """
    Create a new collection in Milvus for storing Re-ID vectors.

    @param   collection_name     Name of the collection to create
    @param   similarity_metric   Metric for computing similarity scores (L2, IP, etc.)
    @param   dimensions          Dimensions of the Re-ID vectors
    @return  None
    """
    try:
      if self.client is None:
        log.warning("Milvus client is not connected")
        return
      
      # Check if collection already exists
      if self.client.has_collection(collection_name):
        log.info(f"Collection {collection_name} already exists")
        return
      
      # Create collection with simple schema
      # Using a simpler approach compatible with MilvusClient
      collection_params = {
        "collection_name": collection_name,
        "dimension": dimensions,
        "primary_fieldname": "id",
        "id_type": "int64",
        "vector_field_name": "embedding",
        "metric_type": similarity_metric,
      }
      
      self.client.create_collection(**collection_params)
      log.info(f"Created Milvus collection {collection_name}")
    except Exception as e:
      log.warning(f"Failed to add schema to Milvus: {e}")
    return

  def addEntry(self, uuid, rvid, object_type, reid_vectors, collection_name=COLLECTION_NAME):
    """
    Add Re-ID vectors to the Milvus collection.

    @param   uuid               Unique ID for the object
    @param   rvid               ID of the object from the motion tracker
    @param   object_type        Class of the object (Person, Vehicle, etc.)
    @param   reid_vectors       Re-ID embeddings produced by a detection model
    @param   collection_name    Name of the collection to add entries to
    @return  None
    """
    try:
      if self.client is None:
        log.warning("Milvus client is not connected")
        return
      
      with self.lock:
        if not reid_vectors or len(reid_vectors) == 0:
          log.warning("No re-id vectors provided")
          return
        
        # Prepare data for insertion
        data = []
        for idx, reid_vector in enumerate(reid_vectors):
          # Ensure vector is 1D array
          if len(reid_vector.shape) > 1:
            reid_vector = reid_vector.flatten()
          
          self.id_counter += 1
          data.append({
            "id": self.id_counter,
            "embedding": reid_vector.tolist(),
            "uuid": str(uuid),
            "rvid": str(rvid),
            "type": str(object_type),
          })
        
        # Insert data into collection
        res = self.client.insert(
          collection_name=collection_name,
          data=data,
        )
        log.debug(f"Inserted {len(data)} entries for uuid {uuid}")
    except Exception as e:
      log.warning(f"Failed to add entry to Milvus: {e}")
    return

  def findSchema(self, collection_name):
    """
    Check whether a collection with a given name exists in Milvus.

    @param   collection_name  Name of the collection to check
    @return  bool             True if collection exists; otherwise False
    """
    try:
      if self.client is None:
        log.warning("Milvus client is not connected")
        return False
      
      return self.client.has_collection(collection_name)
    except Exception as e:
      log.warning(f"Failed to check if collection exists in Milvus: {e}")
      return False

  def findSimilarityScores(self, object_type, reid_vectors, collection_name=COLLECTION_NAME,
                           k_neighbors=K_NEIGHBORS):
    """
    Search the Milvus collection for entries with the closest similarity scores.

    @param   object_type       Class of the source object (Person, Vehicle, etc.)
    @param   reid_vectors      Re-ID embeddings to search for
    @param   collection_name   Name of the collection to search
    @param   k_neighbors       Number of similar entries to return
    @return  list              Results with closest similarity scores, or None if search fails
    """
    try:
      if self.client is None:
        log.warning("Milvus client is not connected")
        return None
      
      if not reid_vectors or len(reid_vectors) == 0:
        log.warning("No re-id vectors provided for similarity search")
        return None
      
      results = []
      with self.lock:
        for reid_vector in reid_vectors:
          # Ensure vector is 1D array
          if len(reid_vector.shape) > 1:
            reid_vector = reid_vector.flatten()
          
          # Search for similar vectors
          search_result = self.client.search(
            collection_name=collection_name,
            data=[reid_vector.tolist()],
            filter=f'type == "{object_type}"',
            limit=k_neighbors,
            output_fields=["uuid", "rvid", "type"]
          )
          
          if search_result and len(search_result) > 0:
            # Convert Milvus search results to match VDMS format
            entities = []
            for result in search_result[0]:
              entities.append({
                "uuid": result["entity"]["uuid"],
                "rvid": result["entity"]["rvid"],
                "_distance": result["distance"]
              })
            results.append(entities)
          else:
            results.append([])
      
      return results if results else None
    except Exception as e:
      log.warning(f"Failed to find similarity scores in Milvus: {e}")
      return None
