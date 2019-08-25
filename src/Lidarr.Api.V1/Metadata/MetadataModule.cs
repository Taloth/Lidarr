using Nancy.Configuration;
﻿using NzbDrone.Core.Extras.Metadata;

namespace Lidarr.Api.V1.Metadata
{
    public class MetadataModule : ProviderModuleBase<MetadataResource, IMetadata, MetadataDefinition>
    {
        public static readonly MetadataResourceMapper ResourceMapper = new MetadataResourceMapper();

        public MetadataModule(INancyEnvironment environment, IMetadataFactory metadataFactory)
            : base(environment,  metadataFactory, "metadata", ResourceMapper)
        {
        }

        protected override void Validate(MetadataDefinition definition, bool includeWarnings)
        {
            if (!definition.Enable) return;
            base.Validate(definition, includeWarnings);
        }
    }
}