using System.Collections.Generic;
using FluentValidation;
using FluentValidation.Results;
using NzbDrone.Common.Extensions;
using NzbDrone.Core.Profiles.Releases;
using Lidarr.Http;
using Nancy.Configuration;

namespace Lidarr.Api.V1.Profiles.Release
{
    public class ReleaseProfileModule : LidarrRestModule<ReleaseProfileResource>
    {
        private readonly IReleaseProfileService _releaseProfileService;


        public ReleaseProfileModule(INancyEnvironment environment, IReleaseProfileService releaseProfileService)
        : base(environment)
        {
            _releaseProfileService = releaseProfileService;

            GetResourceById = Get;
            GetResourceAll = GetAll;
            CreateResource = Create;
            UpdateResource = Update;
            DeleteResource = Delete;

            SharedValidator.RuleFor(d => d).Custom((restriction, context) =>
            {
                if (restriction.Ignored.IsNullOrWhiteSpace() && restriction.Required.IsNullOrWhiteSpace() && restriction.Preferred.Empty())
                {
                    context.AddFailure("'Must contain', 'Must not contain' or 'Preferred' is required");
                }
            });
        }

        private ReleaseProfileResource Get(int id)
        {
            return _releaseProfileService.Get(id).ToResource();
        }

        private List<ReleaseProfileResource> GetAll()
        {
            return _releaseProfileService.All().ToResource();
        }

        private int Create(ReleaseProfileResource resource)
        {
            return _releaseProfileService.Add(resource.ToModel()).Id;
        }

        private void Update(ReleaseProfileResource resource)
        {
            _releaseProfileService.Update(resource.ToModel());
        }

        private void Delete(int id)
        {
            _releaseProfileService.Delete(id);
        }
    }
}
