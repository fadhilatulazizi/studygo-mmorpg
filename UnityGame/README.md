# Unity Game Client

This directory documents the Unity client setup. The Unity Editor project files and binary assets are not committed yet.

## Initial target
- Unity 6 LTS (confirm exact editor version before team setup).
- Android as the first client platform.
- 2D instanced gameplay.
- 3D character and equipment preview.
- C# client code; authoritative gameplay state remains on the server.

## Suggested Assets layout
- Scenes/
- Scripts/{Bootstrap,Networking,World,Combat,Characters,UI}/
- Prefabs/
- Art/{Sprites,Models,Materials,Animations}/
- Audio/
- AddressableAssetsData/

## Model pipeline
Use Blender to inspect, rig and animate source GLB/FBX models. For GLB import, add and pin a maintained glTF importer such as glTFast compatible with the selected Unity version. Verify support for mesh compression and quantization extensions used by source assets.
