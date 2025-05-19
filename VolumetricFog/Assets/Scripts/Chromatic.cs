using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


[ExecuteAlways]
public class Chromatic : MonoBehaviour
{
    [SerializeField] private float intensity = 0f;
    [SerializeField] private Volume volume;

    private void Update()
    {
        if (volume.profile.TryGet(out ColorAdjustments colorAdjustments))
        {
            colorAdjustments.postExposure.value = intensity;
        }
    }
}