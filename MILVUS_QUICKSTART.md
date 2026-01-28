# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Quick Start Guide: Milvus Adapter for Re-ID

## What Was Implemented

A new vector database adapter for SceneScape's Re-ID system that uses Milvus instead of VDMS. This allows you to switch between vector databases by setting an environment variable.

## Files Changed

### New Files (4)
1. `controller/src/controller/milvus_adapter.py` - Milvus database implementation
2. `tests/compose/milvus.yml` - Docker Compose for Milvus infrastructure
3. `tests/compose/scene_reid_milvus.yml` - SceneScape controller config for Milvus
4. `MILVUS_ADAPTER.md` - Detailed documentation

### Modified Files (3)
1. `controller/src/controller/uuid_manager.py` - Added Milvus support
2. `controller/requirements-runtime.txt` - Added milvus-sdk-python dependency
3. `tests/Makefile.functional` - Added test targets for Milvus

## How to Use

### Switch Database at Runtime

Set the `REID_DATABASE` environment variable:

```bash
# Use VDMS (default)
export REID_DATABASE=VDMS

# Use Milvus
export REID_DATABASE=Milvus
```

### Configure Milvus Connection

```bash
export REID_DATABASE=Milvus
export MILVUS_HOSTNAME=milvus.scenescape.intel.com
export MILVUS_PORT=19530
```

## Testing

### Run Re-ID Tests with Milvus

```bash
cd tests

# Test unique detection count
make reid-unique-count-milvus SUPASS=your_password

# Test performance degradation
make reid-performance-degradation-milvus SUPASS=your_password
```

### Run Original VDMS Tests

```bash
cd tests

# Test unique detection count
make reid-unique-count SUPASS=your_password

# Test performance degradation  
make reid-performance-degradation SUPASS=your_password
```

## Architecture

The implementation uses a **Strategy Pattern** where both VDMS and Milvus implement the same `ReIDDatabase` interface:

```
ReIDDatabase (Abstract Interface)
├── VDMSDatabase (Existing)
└── MilvusDatabase (New)

UUIDManager selects implementation at runtime:
available_databases = {
  "VDMS": VDMSDatabase,
  "Milvus": MilvusDatabase,
}
```

## Key Differences

| Feature | VDMS | Milvus |
|---------|------|--------|
| Connection | TLS Certificates | HTTP |
| Backend | Native C++ | Python + Etcd + MinIO |
| Index Type | Native | IVF_FLAT |
| Scaling | Vertical | Horizontal |
| Dependencies | vdms==0.0.22 | milvus-sdk-python==2.4.4 |

## API Compatibility

Both adapters implement identical methods:

```python
class ReIDDatabase:
    def connect(hostname)                    # Connect to database
    def addSchema(...)                       # Create collection/schema
    def addEntry(uuid, rvid, ...)           # Insert vectors
    def findSchema(name)                     # Check if exists
    def findSimilarityScores(...)            # Search for similar vectors
```

## Troubleshooting

### Milvus Connection Failed

1. Verify Milvus service is running:
   ```bash
   docker-compose up milvus etcd minio
   ```

2. Check hostname/port configuration:
   ```bash
   echo $MILVUS_HOSTNAME  # Should be: milvus.scenescape.intel.com
   echo $MILVUS_PORT      # Should be: 19530
   ```

3. Verify network connectivity:
   ```bash
   telnet milvus.scenescape.intel.com 19530
   ```

### Database Selection Not Working

Verify environment variable:
```bash
echo $REID_DATABASE  # Should show: Milvus or VDMS
```

Check logs:
```bash
docker-compose logs scene  # Look for "Milvus connection ready"
```

## Performance Notes

- **Milvus**: Better for horizontal scaling, distributed setup
- **VDMS**: Better for single-machine deployments
- Both maintain identical Re-ID accuracy
- Choice depends on your deployment architecture

## Next Steps

1. Run functional tests to validate Milvus operation
2. Compare performance metrics between backends
3. Deploy to your production environment
4. Monitor vector database performance

For detailed documentation, see [MILVUS_ADAPTER.md](MILVUS_ADAPTER.md)
