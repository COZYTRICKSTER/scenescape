# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import os
import socket
import threading

import numpy as np
from pymilvus import MilvusClient
from pymilvus.client.types import ConsistencyLevel

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
      self.client = MilvusClient(uri=uri, pool_size=10)
      
      # Ensure collection exists on first connection
      self._ensure_collection_exists()
      log.info(f"Milvus connection ready to {hostname}:{DEFAULT_PORT}")
    except socket.error as e:
      log.error(f"Failed to connect to Milvus container: {e}")
    except Exception as e:
      log.error(f"Failed to initialize Milvus client: {e}")
    return

  def _ensure_collection_exists(self):
    """Ensure the collection exists, create if it doesn't."""
    try:
      if self.client is None:
        return False
      
      if not self.findSchema(self.collection_name):
        if not self.addSchema(self.collection_name, self.similarity_metric, self.dimensions):
          log.error("Failed to create collection during connection")
          return False
      return True
    except Exception as e:
      log.error(f"Failed to ensure collection exists: {e}")
      return False

  def addSchema(self, collection_name, similarity_metric, dimensions):
    """
    Create a new collection in Milvus for storing Re-ID vectors.

    @param   collection_name     Name of the collection to create
    @param   similarity_metric   Metric for computing similarity scores (L2, IP, etc.)
    @param   dimensions          Dimensions of the Re-ID vectors
    @return  bool                True if collection exists/created; False otherwise
    """
    try:
      if self.client is None:
        log.warning("Milvus client is not connected")
        return False
      
      # Check if collection already exists
      if self.client.has_collection(collection_name):
        log.debug(f"Collection {collection_name} already exists")
        return True
      
      # Create collection schema compatible with MilvusClient
      # MilvusClient.create_collection() uses simplified parameters
      self.client.create_collection(
        collection_name=collection_name,
        dimension=dimensions,
        metric_type=similarity_metric,
        auto_id=True,
        consistency_level=ConsistencyLevel.SESSION,
      )
      
      # Verify collection was created
      if self.client.has_collection(collection_name):
        log.info(f"Created Milvus collection {collection_name}")
        return True
      else:
        log.error(f"Collection {collection_name} was not created")
        return False
    except Exception as e:
      log.error(f"Failed to add schema to Milvus: {e}")
      return False

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
      
      # Ensure collection exists before adding entries
      if not self.findSchema(collection_name):
        if not self.addSchema(collection_name, self.similarity_metric, self.dimensions):
          log.error(f"Failed to create collection {collection_name} for adding entries")
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
            "vector": reid_vector.tolist(),
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
      
      # Ensure collection exists before searching
      if not self.findSchema(collection_name):
        log.warning(f"Collection {collection_name} does not exist, cannot search")
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
          
          # Search for similar vectors (using collection's session consistency)
          search_result = self.client.search(
            collection_name=collection_name,
            data=[reid_vector.tolist()],
            limit=k_neighbors,
          )
          
          if search_result and len(search_result) > 0:
            # Convert Milvus search results to match VDMS format
            # search_result is a list of lists: [[result1, result2, ...], ...]
            entities = []
            for result in search_result[0]:
              # Each result is a dict with 'id' and 'distance' keys
              entities.append({
                "uuid": str(result.get("id", "")),
                "rvid": str(result.get("id", "")),
                "_distance": result.get("distance", 0.0)
              })
            results.append(entities)
          else:
            results.append([])
      
      return results if results else None
    except Exception as e:
      log.warning(f"Failed to find similarity scores in Milvus: {e}")
      return None
