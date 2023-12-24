using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Unity.VisualScripting;
using UnityEngine;

public class CloudManager : MonoBehaviour {
    [System.Serializable]
    public struct NoiseLayer {
        public Vector3 offset;
        public float scale;
        [Range(-1, 1)]
        public float opacity;
        public int noiseType;
    }

    public List<NoiseLayer> noiseLayers;
    private ComputeBuffer layerBuffer;

    public ComputeShader NoiseGenerator;
    public ComputeShader LightIntensityCalculator;

    public Vector3 cloudSize;
    public Vector3 textureFitSize;
    public int texSize = 256;
    [SerializeField]
    private Vector3Int textureSize;
    public Vector3 textureOffset;
    public bool Animate = false;
    public Vector3 animationSpeed;

    [SerializeField]
    RenderTexture DensityTexture = null;

    public Texture2D NoiseTexture = null;

    public Material material;
    [Range(0, 1)]
    public float minDensity = 0;
    [Range(0, 1)]
    public float maxDensity = 1;

    public float stepSize = 1;
    [Range(0, 1)]
    public float opacity = 1;
    [Range(0, 1)]
    public float opacityThreshold = 1;
    public bool UpdateTextures = true;

    public float LightMarchStepSize = 2;
    public float LightBaseIntensity = 0.2f;
    public float LightAbsorptionCoefficient = 0.01f; 

    public float exposure = 2;

    public GameObject lightObject;

    private MeshFilter meshFilter;
    private MeshRenderer meshRenderer;
    private Mesh mesh;

    public Texture2D simpleNoiseTex;

    void Start() {
        layerBuffer = new ComputeBuffer(20, 6 * sizeof(float));

        mesh = CreateMesh();
        meshFilter = gameObject.AddComponent<MeshFilter>();
        meshFilter.mesh = mesh;

        meshRenderer = gameObject.AddComponent<MeshRenderer>();
        meshRenderer.material = material; 

        CreateTextures();
        CalculateCloudData();
        CalculateLightIntensity();
    }

    // Update is called once per frame
    void Update() {
        if(Animate) {
            float time = Time.deltaTime;

            textureOffset.x += time * animationSpeed.x;
            textureOffset.y += time * animationSpeed.y;
            textureOffset.z += time * animationSpeed.z;
        }

        SetMaterialProperties();

        if (UpdateTextures) {
            CalculateCloudData();
        }
        if(Input.GetKeyDown(KeyCode.F)) {
            CalculateCloudData();
            CalculateLightIntensity();
        }
    }

    private Mesh CreateMesh() {
        Mesh mesh = new Mesh();

        List<Vector3> vertices = new List<Vector3>() {
            new Vector3(0, 0, 0),                                  //0 
            new Vector3(0, cloudSize.y, 0),                        //1
            new Vector3(cloudSize.x, cloudSize.y, 0),              //2
            new Vector3(cloudSize.x, 0, 0),                        //3
            new Vector3(cloudSize.x, 0, cloudSize.z),              //4
            new Vector3(cloudSize.x, cloudSize.y, cloudSize.z),    //5
            new Vector3(0, cloudSize.y, cloudSize.z),              //6
            new Vector3(0, 0, cloudSize.z),                        //7
        };

        for (int i = 0; i < vertices.Count; i++) {
            vertices[i] -= cloudSize / 2.0f;
        }

        List<int> indices = new List<int>() {
            0,1,2, 0,2,3,
            3,2,5, 3,5,4,
            4,5,6, 4,6,7,
            7,6,1, 7,1,0,
            1,6,5, 1,5,2,
            7,0,3, 7,3,4
        };

        mesh.vertices = vertices.ToArray();
        mesh.triangles = indices.ToArray();

        return mesh;
    }

    void CreateTextures() {
        float maxBoundSize = Mathf.Max(Mathf.Max(textureFitSize.x, textureFitSize.y), textureFitSize.z);
        textureSize.x = Mathf.CeilToInt(texSize * textureFitSize.x / maxBoundSize);
        textureSize.y = Mathf.CeilToInt(texSize * textureFitSize.y / maxBoundSize);
        textureSize.z = Mathf.CeilToInt(texSize * textureFitSize.z / maxBoundSize);

        DensityTexture = new RenderTexture(textureSize.x, textureSize.y,0, RenderTextureFormat.RG32, 0);
        DensityTexture.volumeDepth = textureSize.z;
        DensityTexture.enableRandomWrite = true;
        DensityTexture.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        //DensityTexture.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32_SFloat;

        //DensityTexture.useMipMap = true;
        DensityTexture.wrapMode = TextureWrapMode.Mirror;
        DensityTexture.filterMode = FilterMode.Trilinear;
        DensityTexture.autoGenerateMips = false;

        DensityTexture.Create();


        NoiseTexture = new Texture2D(32, 32, TextureFormat.R8, false);
        NoiseTexture.filterMode = FilterMode.Point;
        NoiseTexture.wrapMode = TextureWrapMode.Repeat;

        Color[] noise = new Color[32 * 32];
        for (int i = 0; i < noise.Length; i++) {
            noise[i] = new Color(Random.value, 0, 0, 1);
        }

        NoiseTexture.SetPixels(noise);
        NoiseTexture.Apply();
    }

    void CalculateCloudData() {
        int kernelIndex = NoiseGenerator.FindKernel("NoiseGenerator");

        if (kernelIndex != -1) {
            layerBuffer.SetData(noiseLayers.ToArray());

            NoiseGenerator.SetTexture(kernelIndex, "VolumeTex", DensityTexture);
            NoiseGenerator.SetBuffer(kernelIndex, "noiseLayers", layerBuffer);
            NoiseGenerator.SetInt("layerCount", noiseLayers.Count);
            NoiseGenerator.SetInts("texSize", textureSize.x, textureSize.y, textureSize.z);

            NoiseGenerator.Dispatch(kernelIndex, texSize / 4 + 1, texSize / 4 + 1, texSize / 4 + 1);


        }
    }

    private void CalculateLightIntensity() {
        int kernelIndex = LightIntensityCalculator.FindKernel("LightMarch");

        if(kernelIndex != -1) {
            RenderTexture CopyTexture = new RenderTexture(DensityTexture.width, DensityTexture.height, 0, RenderTextureFormat.R16, 0);
            CopyTexture.enableRandomWrite = true;
            CopyTexture.volumeDepth = DensityTexture.volumeDepth;
            CopyTexture.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            CopyTexture.Create();

            LightIntensityCalculator.SetTexture(kernelIndex, "CloudData", DensityTexture);
            LightIntensityCalculator.SetTexture(kernelIndex, "CopyTex", CopyTexture);
            
            LightIntensityCalculator.SetVector("_BoundMin",textureFitSize / 2.0f * -1.0f);
            LightIntensityCalculator.SetVector("_BoundMax", textureFitSize / 2.0f);

            LightIntensityCalculator.SetInts("_TexSize", textureSize.x, textureSize.y, textureSize.z);
            
            LightIntensityCalculator.SetVector("_LightDirection", lightObject.transform.forward);
            LightIntensityCalculator.SetFloat("_LightMarchStepSize", LightMarchStepSize);
            LightIntensityCalculator.SetFloat("_LightBaseIntensity", LightBaseIntensity);
            LightIntensityCalculator.SetFloat("_LightAbsorptionCoefficient", LightAbsorptionCoefficient);

            LightIntensityCalculator.SetFloat("_MinDensity", minDensity);
            LightIntensityCalculator.SetFloat("_MaxDensity", maxDensity);
            LightIntensityCalculator.SetFloat("_Opacity", opacity);

            LightIntensityCalculator.Dispatch(kernelIndex, textureSize.x / 4 + 1, textureSize.y / 4 + 1, textureSize.z / 4 + 1);

            kernelIndex = LightIntensityCalculator.FindKernel("CopyLightIntensity");

            if(kernelIndex != -1) {
                LightIntensityCalculator.SetInts("_TexSize", textureSize.x, textureSize.y, textureSize.z);

                LightIntensityCalculator.SetTexture(kernelIndex, "_CloudData", DensityTexture);
                LightIntensityCalculator.SetTexture(kernelIndex, "_CopyTex", CopyTexture);

                LightIntensityCalculator.Dispatch(kernelIndex, textureSize.x / 4 + 1, textureSize.y / 4 + 1, textureSize.z / 4 + 1);
            }

            Destroy(CopyTexture);

            //DensityTexture.GenerateMips();
        }
    }

    void SetMaterialProperties() {
        material.SetTexture("_DensityTex", DensityTexture);
        material.SetTexture("_NoiseTex", NoiseTexture);

        material.SetFloat("_StepSize", stepSize);
        material.SetFloat("_Opacity", opacity);
        material.SetFloat("_OpacityThreshold", opacityThreshold);

        material.SetVector("_LightDir", lightObject.transform.forward);

        material.SetFloat("_MinDensity", minDensity);
        material.SetFloat("_MaxDensity", maxDensity);

        material.SetVector("_BoundMin", cloudSize / -2.0f);
        material.SetVector("_BoundMax", cloudSize / 2.0f);

        material.SetVector("_TextureFitSize", textureFitSize);
        material.SetVector("_TextureOffset", textureOffset);

        material.SetVector("_LightDirection", lightObject.transform.forward);
        material.SetFloat("_LightMarchStepSize", LightMarchStepSize);
        material.SetFloat("_LightBaseIntensity", LightBaseIntensity);
        material.SetFloat("_LightAbsorptionCoefficient", LightAbsorptionCoefficient);

        material.SetFloat("_Exposure", exposure);
    }
}
