using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Harumaron
{
	[DisallowMultipleComponent]
	[RequireComponent(typeof(Light), typeof(UniversalAdditionalLightData))]
	public sealed class VolumetricAdditionalLight : MonoBehaviour
	{
		[Range(-1.0f, 1.0f)]
		[SerializeField]
		[Header("異方性: -1.0f = 逆方向に拡散, 1.0f = 光の方向に拡散")]
		private float anisotropy = 0.25f;
		[Range(0.0f, 16.0f)]
		[Header("散乱係数: カメラに届く光の強さ")]
		[SerializeField] private float scattering = 1.0f;
		[Range(0.0f, 1.0f)]
		[Header("光の影響範囲")]
		[SerializeField] private float radius = 0.2f;

		public float Anisotropy
		{
			get => anisotropy;
			set => anisotropy = Mathf.Clamp(value, -1.0f, 1.0f);
		}

		public float Scattering
		{
			get => scattering;
			set => scattering = Mathf.Clamp(value, 0.0f, 16.0f);
		}

		public float Radius
		{
			get => radius;
			set => radius = Mathf.Clamp01(value);
		}
	}
}